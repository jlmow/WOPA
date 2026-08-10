import { useEffect, useState } from "react";
import type { PickingTask } from "./types";
import { pickingApi } from "./api";
import { TaskList } from "./components/TaskList";
import { ScanTask } from "./components/ScanTask";

export default function App() {
  const [tasks, setTasks] = useState<PickingTask[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);

  useEffect(() => {
    pickingApi
      .listTasks()
      .then(setTasks)
      .catch((err) => setLoadError((err as Error).message));
  }, []);

  function handleUpdated(updated: PickingTask) {
    setTasks((prev) => prev.map((t) => (t.id === updated.id ? updated : t)));
  }

  // Ao concluir uma tarefa, avança automaticamente para a próxima da rota
  // (a lista já vem ordenada por localização) — o operador não tem de
  // voltar à lista e escolher manualmente a tarefa seguinte.
  function handleCompleted(taskId: string) {
    const next = tasks.find((t) => t.id !== taskId && t.estado !== "Concluida");
    setSelectedId(next ? next.id : null);
  }

  const selectedTask = tasks.find((t) => t.id === selectedId) ?? null;
  const waveComplete = tasks.length > 0 && tasks.every((t) => t.estado === "Concluida");

  return (
    <main className="app">
      <header className="app__header">
        <h1>WOPA · Picking</h1>
      </header>

      {loadError && <p className="scan-screen__message scan-screen__message--erro">{loadError}</p>}

      {!selectedTask && waveComplete && (
        <p className="scan-screen__message scan-screen__message--info" data-testid="wave-complete">
          Onda concluída! Todas as tarefas foram picadas.
        </p>
      )}

      {!selectedTask && <TaskList tasks={tasks} onSelect={(t) => setSelectedId(t.id)} />}

      {selectedTask && (
        <ScanTask
          task={selectedTask}
          onUpdated={handleUpdated}
          onCompleted={handleCompleted}
          onBack={() => setSelectedId(null)}
        />
      )}
    </main>
  );
}
