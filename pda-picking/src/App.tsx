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

  const selectedTask = tasks.find((t) => t.id === selectedId) ?? null;

  return (
    <main className="app">
      <header className="app__header">
        <h1>WOPA · Picking</h1>
      </header>

      {loadError && <p className="scan-screen__message scan-screen__message--erro">{loadError}</p>}

      {!selectedTask && <TaskList tasks={tasks} onSelect={(t) => setSelectedId(t.id)} />}

      {selectedTask && (
        <ScanTask task={selectedTask} onUpdated={handleUpdated} onBack={() => setSelectedId(null)} />
      )}
    </main>
  );
}
