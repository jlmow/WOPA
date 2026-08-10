import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import type { PickingTask } from "./types";
import { pickingApi } from "./api";
import { TaskList } from "./components/TaskList";
import { ScanTask } from "./components/ScanTask";
import { useSession } from "../../app/SessionContext";

type Vista = "carregando" | "leitura" | "lista" | "concluida";

export function PickingModule() {
  const { zona } = useSession();
  const navigate = useNavigate();
  const [tasks, setTasks] = useState<PickingTask[]>([]);
  const [missaoCodigo, setMissaoCodigo] = useState<string | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [vista, setVista] = useState<Vista>("carregando");
  const [erro, setErro] = useState<string | null>(null);

  // Ao entrar no módulo, a missão começa logo na primeira linha pendente —
  // o operador não escolhe por onde começar, o sistema decide pela rota.
  useEffect(() => {
    Promise.all([pickingApi.listTasks(), pickingApi.getMission()])
      .then(([lista, missao]) => {
        setTasks(lista);
        setMissaoCodigo(missao.codigo);
        const primeira = lista.find((t) => t.estado !== "Concluida");
        if (primeira) {
          setSelectedId(primeira.id);
          setVista("leitura");
        } else {
          setVista("concluida");
        }
      })
      .catch((err) => setErro((err as Error).message));
  }, []);

  function handleUpdated(updated: PickingTask) {
    setTasks((prev) => prev.map((t) => (t.id === updated.id ? updated : t)));
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
            Missão {missaoCodigo ?? "…"} · Zona {zona?.codigo}
          </p>
          <button className="link-button" onClick={() => navigate("/modulos")} data-testid="voltar-modulos">
            Módulos
          </button>
        </div>
        <h1>Picking</h1>
        {total > 0 && (
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

      {vista === "concluida" && total > 0 && (
        <div className="mission-complete" data-testid="mission-complete">
          <h2>Missão concluída</h2>
          <p>
            {total} linha{total === 1 ? "" : "s"} separada{total === 1 ? "" : "s"}. Segue para o packing.
          </p>
          <button className="confirm-button" onClick={() => navigate("/modulos")} data-testid="voltar-modulos-fim">
            Voltar aos módulos
          </button>
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
          onUpdated={handleUpdated}
          onCompleted={handleCompleted}
          onVerLista={() => setVista("lista")}
        />
      )}
    </main>
  );
}
