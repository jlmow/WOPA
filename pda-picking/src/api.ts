import type { ErrorResponse, PickingTask } from "./types";

const API_BASE_URL = import.meta.env.VITE_ORCHESTRATOR_URL ?? "http://localhost:5080";

async function handle<T>(response: Response): Promise<T> {
  const body = await response.json();
  if (!response.ok) {
    const error = body as ErrorResponse;
    throw new Error(error.erro ?? "Erro desconhecido a comunicar com o orchestrator.");
  }
  return body as T;
}

export const pickingApi = {
  listTasks: (): Promise<PickingTask[]> =>
    fetch(`${API_BASE_URL}/api/picking/tasks`).then((r) => handle(r)),

  getTask: (id: string): Promise<PickingTask> =>
    fetch(`${API_BASE_URL}/api/picking/tasks/${id}`).then((r) => handle(r)),

  scan: (id: string, barcode: string): Promise<PickingTask> =>
    fetch(`${API_BASE_URL}/api/picking/tasks/${id}/scan`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ barcode }),
    }).then((r) => handle(r)),

  confirm: (id: string): Promise<PickingTask> =>
    fetch(`${API_BASE_URL}/api/picking/tasks/${id}/confirm`, {
      method: "POST",
    }).then((r) => handle(r)),
};
