import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useLiveQuery } from "dexie-react-hooks";
import type { MissionSummary, PickingTask } from "./types";
import { pickingApi } from "./api";
import { db } from "./db";
import { flushOutbox } from "./sync";
import { TaskList } from "./components/TaskList";
import { ScanTask } from "./components/ScanTask";
import { PickAlveolo } from "./components/PickAlveolo";
import { MontarPlataforma } from "./components/MontarPlataforma";
import { SyncBadge } from "./components/SyncBadge";
import { useSession } from "../../app/SessionContext";
import { useServerConnection } from "../../shared/useServerConnection";
import { gerarOperacaoId } from "../../shared/id";

// "picking": depois de um scan válido, passo obrigatório de escolher
// alvéolo + quantidade (ADR-022) antes de a leitura seguinte ser possível.
// "montagem" (ADR-029): gate antes de tudo isto — sem plataforma
// montada/confirmada não há leitura de artigos.
type Vista = "carregando" | "montagem" | "leitura" | "picking" | "lista" | "concluida";

const MISSAO_CODIGO_CHAVE = "missaoCodigo";

export function PickingModule() {
  const { zona } = useSession();
  const navigate = useNavigate();
  const ligado = useServerConnection();
  const pendentes = useLiveQuery(() => db.outbox.count(), [], 0);
  const [tasks, setTasks] = useState<PickingTask[]>([]);
  const [missao, setMissao] = useState<MissionSummary | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [vista, setVista] = useState<Vista>("carregando");
  const [erro, setErro] = useState<string | null>(null);

  function avancarAposGate(lista: PickingTask[]) {
    const primeira = lista.find((t) => t.estado !== "Concluida");
    if (primeira) {
      setSelectedId(primeira.id);
      setVista("leitura");
    } else {
      setVista("concluida");
    }
  }

  function iniciarComLista(lista: PickingTask[], missaoAtual: MissionSummary) {
    setTasks(lista);
    setMissao(missaoAtual);
    if (missaoAtual.montagem && !missaoAtual.montagem.confirmada) {
      setVista("montagem");
      return;
    }
    avancarAposGate(lista);
  }

  async function handleMontagem(
    matriculaPalete: string,
    matriculasCestos: string[],
  ): Promise<{ ok: true } | { ok: false; erro: string }> {
    if (!missao) return { ok: false, erro: "Sem missão carregada." };
    try {
      await pickingApi.montar(missao.id, matriculaPalete, matriculasCestos, gerarOperacaoId());
      const missaoConfirmada: MissionSummary = {
        ...missao,
        montagem: missao.montagem ? { ...missao.montagem, confirmada: true } : null,
      };
      setMissao(missaoConfirmada);
      avancarAposGate(tasks);
      return { ok: true };
    } catch (err) {
      return { ok: false, erro: (err as Error).message || "Não foi possível confirmar a plataforma." };
    }
  }

  function aplicarSincronizado(taskId: string, atualizado: PickingTask) {
    setTasks((prev) => prev.map((t) => (t.id === taskId ? atualizado : t)));
  }

  // Ao entrar no módulo: primeiro tenta despachar o que já estava pendente
  // de uma sessão anterior (para não pedir dados frescos ao servidor antes
  // de ele saber do que já foi feito offline), depois tenta obter a missão
  // atual da rede — e só recorre à cópia local (IndexedDB) se não houver
  // ligação. É assim que o módulo continua a funcionar sem rede (ADR-007).
  useEffect(() => {
    let cancelado = false;

    async function carregar() {
      await flushOutbox(aplicarSincronizado);
      if (cancelado) return;

      try {
        const [lista, missaoRemota] = await Promise.all([pickingApi.listTasks(), pickingApi.getMission()]);
        if (cancelado) return;
        await db.tasks.bulkPut(lista);
        await db.meta.put({ chave: MISSAO_CODIGO_CHAVE, valor: missaoRemota.codigo });
        iniciarComLista(lista, missaoRemota);
      } catch {
        if (cancelado) return;
        const [localTasks, localMeta] = await Promise.all([
          db.tasks.toArray(),
          db.meta.get(MISSAO_CODIGO_CHAVE),
        ]);
        if (cancelado) return;
        if (localTasks.length === 0) {
          setErro(
            "Sem ligação e sem missão guardada neste dispositivo. É preciso sincronizar pelo menos uma vez antes de trabalhar offline.",
          );
          return;
        }
        // Offline: se já havia tarefas em cache, o gate de montagem já foi
        // ultrapassado numa sessão anterior online (ver ADR-029) — sem
        // rede não há como validar/montar a plataforma, por isso não se
        // repete aqui.
        iniciarComLista(localTasks, {
          id: "",
          codigo: localMeta?.valor ?? "—",
          totalLinhas: localTasks.length,
          linhasConcluidas: localTasks.filter((t) => t.estado === "Concluida").length,
          montagem: null,
        });
      }
    }

    carregar();
    return () => {
      cancelado = true;
    };
  }, []);

  // Tenta sincronizar sempre que a rede volta, e periodicamente como rede de
  // segurança (o evento "online" do browser nem sempre é fiável).
  useEffect(() => {
    function tentarSincronizar() {
      void flushOutbox(aplicarSincronizado);
    }
    window.addEventListener("online", tentarSincronizar);
    const intervalo = window.setInterval(tentarSincronizar, 5000);
    return () => {
      window.removeEventListener("online", tentarSincronizar);
      window.clearInterval(intervalo);
    };
  }, []);

  // Valida a leitura localmente (o código de barras esperado já está em
  // cache) — sem depender de uma resposta de rede. Já não regista
  // quantidade nenhuma (isso passou para handlePick, ADR-022): um scan
  // válido só confirma o artigo certo e avança automaticamente para a
  // escolha de alvéolo + quantidade.
  async function handleScan(
    task: PickingTask,
    barcode: string,
  ): Promise<{ ok: true } | { ok: false; erro: string }> {
    if (task.estado === "Concluida") {
      return { ok: false, erro: "Linha já concluída." };
    }
    if (task.codigoBarras !== barcode) {
      return { ok: false, erro: "Código de barras não corresponde ao artigo esperado." };
    }

    await db.outbox.add({ opId: gerarOperacaoId(), tipo: "scan", taskId: task.id, barcode, criadoEm: Date.now() });
    void flushOutbox(aplicarSincronizado);
    setVista("picking");
    return { ok: true };
  }

  // Aplica o pick localmente (ADR-007/ADR-022) e decide o próximo passo
  // sozinho: se a linha ainda não está completa, volta à leitura para o
  // resto da quantidade (pode vir de outro alvéolo); se ficou completa, o
  // próprio PickAlveolo mostra a confirmação e chama handleCompleted.
  async function handlePick(task: PickingTask, alveoloId: string, quantidade: number, motivo?: string) {
    const quantidadeLida = Math.min(task.quantidadeLida + quantidade, task.quantidadeAlvo);
    const completo = quantidadeLida >= task.quantidadeAlvo;
    const atualizado: PickingTask = {
      ...task,
      quantidadeLida,
      estado: completo ? "Concluida" : "EmProgresso",
    };

    await db.tasks.put(atualizado);
    const agora = Date.now();
    await db.outbox.add({ opId: gerarOperacaoId(), tipo: "pick", taskId: task.id, alveoloId, quantidade, motivo, criadoEm: agora });
    if (completo) {
      await db.outbox.add({ opId: gerarOperacaoId(), tipo: "confirm", taskId: task.id, criadoEm: agora + 1 });
    }

    setTasks((prev) => prev.map((t) => (t.id === task.id ? atualizado : t)));
    void flushOutbox(aplicarSincronizado);
    if (!completo) setVista("leitura");
  }

  // Ao concluir uma linha, avança automaticamente para a próxima da rota
  // — sem o operador ter de voltar à lista e escolher manualmente.
  function handleCompleted(taskId: string) {
    const proxima = tasks.find((t) => t.id !== taskId && t.estado !== "Concluida");
    if (proxima) {
      setSelectedId(proxima.id);
      setVista("leitura");
    } else {
      setVista("concluida");
    }
  }

  const selectedTask = tasks.find((t) => t.id === selectedId) ?? null;
  const concluidas = tasks.filter((t) => t.estado === "Concluida").length;
  const total = tasks.length;
  const progressoPct = total > 0 ? Math.round((concluidas / total) * 100) : 0;

  return (
    <main className="app">
      <header className="app__header app__header--mission">
        <div className="app__header-row">
          <p className="app__eyebrow">
            Missão {missao?.codigo ?? "…"} · Zona {zona?.codigo}
          </p>
          <button className="link-button" onClick={() => navigate("/modulos")} data-testid="voltar-modulos">
            Módulos
          </button>
        </div>
        <h1>Picking</h1>
        <SyncBadge />
        {total > 0 && vista !== "montagem" && (
          <>
            <div className="mission-progress" data-testid="mission-progress">
              <div className="mission-progress__fill" style={{ width: `${progressoPct}%` }} />
            </div>
            <p className="mission-progress__label">
              {concluidas} de {total} linhas separadas
            </p>
          </>
        )}
      </header>

      {erro && <p className="scan-screen__message scan-screen__message--erro">{erro}</p>}

      {vista === "montagem" && missao?.montagem && (
        <MontarPlataforma montagem={missao.montagem} onConfirmar={handleMontagem} />
      )}

      {vista === "concluida" && total > 0 && (
        <div className="mission-complete" data-testid="mission-complete">
          <h2>Missão concluída</h2>
          <p>
            {total} linha{total === 1 ? "" : "s"} separada{total === 1 ? "" : "s"}. Segue para o packing.
          </p>
          {/* ADR-008: passar para a missão seguinte exige ligação garantida
              ao servidor E a fila desta missão totalmente sincronizada —
              não basta "parecer" online. */}
          <button
            className="confirm-button"
            onClick={() => navigate("/modulos")}
            disabled={!ligado || !!pendentes}
            data-testid="voltar-modulos-fim"
          >
            Voltar aos módulos
          </button>
          {(!ligado || !!pendentes) && (
            <p className="mission-complete__aviso" data-testid="mission-complete-aviso">
              {!ligado
                ? "À espera de ligação ao servidor para terminar a missão…"
                : `A sincronizar ${pendentes} linha(s) por confirmar…`}
            </p>
          )}
        </div>
      )}

      {vista === "lista" && (
        <>
          <button
            className="link-button"
            onClick={() => setVista(selectedTask ? "leitura" : "concluida")}
            data-testid="voltar-leitura"
          >
            &larr; Voltar à leitura
          </button>
          <TaskList
            tasks={tasks}
            onSelect={(t) => {
              setSelectedId(t.id);
              setVista("leitura");
            }}
          />
        </>
      )}

      {vista === "leitura" && selectedTask && (
        <ScanTask
          task={selectedTask}
          onScan={(barcode) => handleScan(selectedTask, barcode)}
          onVerLista={() => setVista("lista")}
        />
      )}

      {vista === "picking" && selectedTask && (
        <PickAlveolo
          task={selectedTask}
          onConfirmar={(alveoloId, quantidade, motivo) => void handlePick(selectedTask, alveoloId, quantidade, motivo)}
          onCancelar={() => setVista("leitura")}
          onCompleted={handleCompleted}
        />
      )}
    </main>
  );
}
