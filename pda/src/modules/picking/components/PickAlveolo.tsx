import { useEffect, useRef, useState } from "react";
import type { AlveoloComStock, PickingTask } from "../types";
import { pickingApi } from "../api";
import { allowKeyboardOnTap, suppressKeyboardOnBlur } from "../../../shared/scannerInput";

interface Props {
  task: PickingTask;
  onConfirmar: (alveoloId: string, matriculaPalete: string, quantidade: number, motivo?: string) => void;
  onCancelar: () => void;
  onCompleted: (taskId: string) => void;
}

const ADVANCE_DELAY_MS = 600;

// Motivos de exceção (ADR-027) — obrigatório escolher um quando a
// quantidade picada difere da sugerida, para não permitir "pico 10 e
// levo 9" sem deixar rasto do porquê.
const MOTIVOS_EXCECAO = ["Falta de stock", "Caixa incompleta", "Dano", "Outro"];

/**
 * Passo obrigatório depois do scan (ADR-022): o operador escolhe de que
 * alvéolo está a separar (lista de stock real, não um valor fixo) e
 * confirma a quantidade. O foco avança sozinho — escolher o alvéolo já
 * põe o cursor no campo de quantidade, pronto a aceitar a sugestão com
 * Enter ou a ser substituído por um número diferente.
 */
export function PickAlveolo({ task, onConfirmar, onCancelar, onCompleted }: Props) {
  const [opcoes, setOpcoes] = useState<AlveoloComStock[] | null>(null);
  const [erroCarregar, setErroCarregar] = useState<string | null>(null);
  const [selecionadoId, setSelecionadoId] = useState<string | null>(null);
  const [matriculaPalete, setMatriculaPalete] = useState<string | null>(null);
  const [paleteInput, setPaleteInput] = useState("");
  const [quantidade, setQuantidade] = useState<number>(0);
  const [motivo, setMotivo] = useState<string>("");
  const [erro, setErro] = useState<string | null>(null);
  const paleteRef = useRef<HTMLInputElement>(null);
  const quantidadeRef = useRef<HTMLInputElement>(null);

  // Quando este pick completa a linha, o próprio orchestrator/estado local
  // já marca a tarefa como Concluída (ver PickingModule.handlePick) — só
  // falta mostrar a confirmação e avançar sozinho para a próxima.
  useEffect(() => {
    if (task.estado !== "Concluida") return;
    const temporizador = window.setTimeout(() => onCompleted(task.id), ADVANCE_DELAY_MS);
    return () => window.clearTimeout(temporizador);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [task.estado, task.id]);

  useEffect(() => {
    let cancelado = false;
    setOpcoes(null);
    setErroCarregar(null);
    pickingApi
      .alveolos(task.id)
      .then((lista) => {
        if (cancelado) return;
        setOpcoes(lista);
        if (lista.length > 0) {
          setSelecionadoId(lista[0].alveoloId);
          setQuantidade(lista[0].sugestaoQuantidade);
        }
      })
      .catch((err) => {
        if (cancelado) return;
        setErroCarregar(
          (err as Error).message || "Sem ligação — não é possível obter os alvéolos com stock agora.",
        );
      });
    return () => {
      cancelado = true;
    };
  }, [task.id]);

  // Escolher o alvéolo avança logo o foco para a leitura da palete de
  // origem (ADR-035: o alvéolo pode ter mais do que uma palete com o
  // mesmo SKU, por isso o operador tem de ler a matrícula certa a cada
  // pick) — sem abrir o teclado sozinho (só no toque real, ver
  // scannerInput).
  function selecionar(opcao: AlveoloComStock) {
    setSelecionadoId(opcao.alveoloId);
    setQuantidade(opcao.sugestaoQuantidade);
    setMatriculaPalete(null);
    setPaleteInput("");
    setMotivo("");
    setErro(null);
    requestAnimationFrame(() => {
      paleteRef.current?.focus();
    });
  }

  function lerPalete(e: React.FormEvent) {
    e.preventDefault();
    if (!paleteInput.trim()) return;
    setMatriculaPalete(paleteInput.trim());
    setPaleteInput("");
    setErro(null);
    requestAnimationFrame(() => {
      quantidadeRef.current?.focus();
    });
  }

  const selecionado = opcoes?.find((o) => o.alveoloId === selecionadoId) ?? null;
  const maximo = selecionado ? Math.min(task.quantidadeAlvo - task.quantidadeLida, selecionado.quantidadeDisponivel) : 0;
  const ehExcecao = selecionado !== null && quantidade !== selecionado.sugestaoQuantidade;

  function confirmarComQuantidade(qtd: number, motivoEscolhido?: string) {
    if (!selecionado || !matriculaPalete) return;
    if (qtd <= 0 || qtd > maximo) {
      setErro(`Introduz uma quantidade entre 1 e ${maximo}.`);
      return;
    }
    if (qtd !== selecionado.sugestaoQuantidade && !motivoEscolhido) {
      setErro("Escolhe um motivo para a quantidade ser diferente da sugerida.");
      return;
    }
    onConfirmar(selecionado.alveoloId, matriculaPalete, qtd, motivoEscolhido);
  }

  // Toque único para o caso comum (caixa fechada, nada de estranho):
  // aceita a sugestão sem tocar no teclado nem escolher motivo nenhum.
  function confirmarSugerido() {
    if (!selecionado) return;
    confirmarComQuantidade(selecionado.sugestaoQuantidade);
  }

  function handleConfirmar(e: React.FormEvent) {
    e.preventDefault();
    confirmarComQuantidade(quantidade, ehExcecao ? motivo || undefined : undefined);
  }

  return (
    <div className="scan-screen" data-testid="pick-alveolo">
      <button className="link-button" onClick={onCancelar} data-testid="cancelar-pick">
        &larr; Ler outro código
      </button>

      <h2>{task.descricao}</h2>
      <p className="scan-screen__meta">
        SKU {task.sku} · Faltam <strong>{task.quantidadeAlvo - task.quantidadeLida}</strong>
      </p>

      {task.estado === "Concluida" && (
        <p className="scan-screen__message scan-screen__message--info" data-testid="message">
          Linha concluída. A avançar…
        </p>
      )}

      {task.estado !== "Concluida" && erroCarregar && (
        <>
          <p className="scan-screen__message scan-screen__message--erro">{erroCarregar}</p>
          <button
            type="button"
            onClick={() => {
              setErroCarregar(null);
              setOpcoes(null);
            }}
            data-testid="tentar-novamente-alveolos"
          >
            Tentar novamente
          </button>
        </>
      )}

      {task.estado !== "Concluida" && opcoes === null && !erroCarregar && <p>A obter alvéolos com stock…</p>}

      {task.estado !== "Concluida" && opcoes !== null && opcoes.length === 0 && (
        <p className="scan-screen__message scan-screen__message--erro">
          Sem stock deste artigo em nenhum alvéolo desta zona.
        </p>
      )}

      {task.estado !== "Concluida" && opcoes !== null && opcoes.length > 0 && (
        <>
          <p className="scan-screen__meta">Em que alvéolo estás?</p>
          <ul className="option-list" data-testid="alveolo-list">
            {opcoes.map((opcao) => (
              <li key={opcao.alveoloId}>
                <button
                  type="button"
                  className={`option-card${opcao.alveoloId === selecionadoId ? " option-card--selecionado" : ""}`}
                  onClick={() => selecionar(opcao)}
                  data-testid={`alveolo-${opcao.alveoloId}`}
                >
                  <span className="option-card__codigo">{opcao.codigo}</span>
                  <span className="option-card__nome">{opcao.quantidadeDisponivel} disponíveis</span>
                </button>
              </li>
            ))}
          </ul>

          {selecionado && matriculaPalete === null && (
            <form onSubmit={lerPalete}>
              <p className="scan-screen__meta">
                Uma palete pode ter mais do que um SKU e um alvéolo pode ter mais do que uma palete — lê a
                matrícula certa antes de picar.
              </p>
              <label htmlFor="pick-palete">Ler matrícula da palete de origem</label>
              <input
                id="pick-palete"
                ref={paleteRef}
                data-testid="palete-origem-input"
                inputMode="none"
                value={paleteInput}
                onChange={(e) => setPaleteInput(e.target.value)}
                onPointerDown={allowKeyboardOnTap}
                onBlur={suppressKeyboardOnBlur}
                onClick={() => setPaleteInput("")}
                placeholder="Ler código da palete"
                autoComplete="off"
              />
              <button type="submit" disabled={!paleteInput.trim()} data-testid="confirmar-palete-origem">
                Confirmar palete
              </button>
            </form>
          )}

          {selecionado && matriculaPalete !== null && (
            <form onSubmit={handleConfirmar}>
              <div className="platform-badge" data-testid="palete-origem-lida">
                Palete de origem <strong>{matriculaPalete}</strong>
                <button
                  type="button"
                  className="link-button"
                  onClick={() => {
                    setMatriculaPalete(null);
                    requestAnimationFrame(() => paleteRef.current?.focus());
                  }}
                  data-testid="reler-palete-origem"
                >
                  Ler outra
                </button>
              </div>

              {!ehExcecao && (
                <button
                  type="button"
                  className="confirm-button"
                  onClick={confirmarSugerido}
                  data-testid="confirmar-sugerido"
                >
                  Confirmar {selecionado.sugestaoQuantidade}
                </button>
              )}

              <label htmlFor="pick-quantidade">
                {ehExcecao ? "Quantidade diferente da sugerida" : "Ou introduz outra quantidade"}
              </label>
              <input
                id="pick-quantidade"
                ref={quantidadeRef}
                data-testid="quantidade-input"
                type="number"
                inputMode="none"
                min={1}
                max={maximo}
                value={quantidade === 0 ? "" : quantidade}
                onChange={(e) => setQuantidade(Number(e.target.value))}
                onPointerDown={allowKeyboardOnTap}
                onBlur={suppressKeyboardOnBlur}
                onClick={() => setQuantidade(0)}
                autoComplete="off"
              />

              {ehExcecao && (
                <>
                  <label htmlFor="pick-motivo">Motivo</label>
                  <select
                    id="pick-motivo"
                    data-testid="motivo-select"
                    value={motivo}
                    onChange={(e) => setMotivo(e.target.value)}
                  >
                    <option value="">Escolher motivo…</option>
                    {MOTIVOS_EXCECAO.map((m) => (
                      <option key={m} value={m}>
                        {m}
                      </option>
                    ))}
                  </select>
                </>
              )}

              <button
                type="submit"
                disabled={quantidade <= 0 || (ehExcecao && !motivo)}
                data-testid="confirmar-pick"
              >
                Confirmar
              </button>
            </form>
          )}

          {erro && (
            <p className="scan-screen__message scan-screen__message--erro" data-testid="pick-erro">
              {erro}
            </p>
          )}
        </>
      )}
    </div>
  );
}
