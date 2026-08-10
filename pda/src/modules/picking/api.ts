import { apiFetch } from "../../shared/api/http";
import type { MissionSummary, PickingTask } from "./types";

export const pickingApi = {
  listTasks: (): Promise<PickingTask[]> => apiFetch<PickingTask[]>("/api/picking/tasks"),

  getMission: (): Promise<MissionSummary> => apiFetch<MissionSummary>("/api/picking/mission"),

  // operacaoId (ADR-007): identifica a operação de forma única, gerada no
  // dispositivo antes de haver rede — permite ao orchestrator reconhecer
  // reenvios e devolver sempre o mesmo resultado, sem duplicar o efeito.
  scan: (id: string, barcode: string, operacaoId: string): Promise<PickingTask> =>
    apiFetch<PickingTask>(`/api/picking/tasks/${id}/scan`, {
      method: "POST",
      body: JSON.stringify({ barcode, operacaoId }),
    }),

  confirm: (id: string, operacaoId: string): Promise<PickingTask> =>
    apiFetch<PickingTask>(`/api/picking/tasks/${id}/confirm`, {
      method: "POST",
      body: JSON.stringify({ operacaoId }),
    }),
};
