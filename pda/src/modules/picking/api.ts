import { apiFetch } from "../../shared/api/http";
import type { MissionSummary, PickingTask } from "./types";

export const pickingApi = {
  listTasks: (): Promise<PickingTask[]> => apiFetch<PickingTask[]>("/api/picking/tasks"),

  getMission: (): Promise<MissionSummary> => apiFetch<MissionSummary>("/api/picking/mission"),

  scan: (id: string, barcode: string): Promise<PickingTask> =>
    apiFetch<PickingTask>(`/api/picking/tasks/${id}/scan`, {
      method: "POST",
      body: JSON.stringify({ barcode }),
    }),

  confirm: (id: string): Promise<PickingTask> =>
    apiFetch<PickingTask>(`/api/picking/tasks/${id}/confirm`, { method: "POST" }),
};
