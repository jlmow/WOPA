import { apiFetch } from "../../shared/api/http";
import type { AlveoloComStock, MissionSummary, PickingTask } from "./types";

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

  // Lista de alvéolos com stock do artigo, na zona da missão (ADR-022) —
  // sempre pedida em direto, nunca em cache: é a única parte deste fluxo
  // que precisa de rede (o pick em si já fica na fila de saída como as
  // outras operações).
  alveolos: (id: string): Promise<AlveoloComStock[]> =>
    apiFetch<AlveoloComStock[]>(`/api/picking/tasks/${id}/alveolos`),

  // motivo (ADR-027): obrigatório no ecrã quando a quantidade difere da
  // sugerida (ex.: "Falta de stock") — ver PickAlveolo.
  pick: (id: string, alveoloId: string, quantidade: number, motivo: string | undefined, operacaoId: string): Promise<PickingTask> =>
    apiFetch<PickingTask>(`/api/picking/tasks/${id}/pick`, {
      method: "POST",
      body: JSON.stringify({ alveoloId, quantidade, motivo, operacaoId }),
    }),

  confirm: (id: string, operacaoId: string): Promise<PickingTask> =>
    apiFetch<PickingTask>(`/api/picking/tasks/${id}/confirm`, {
      method: "POST",
      body: JSON.stringify({ operacaoId }),
    }),
};
