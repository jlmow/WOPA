import { apiFetch } from "./http";

export type PickingTaskStatus = "Pendente" | "EmProgresso" | "Concluida";

export interface PickingTask {
  id: string;
  sku: string;
  descricao: string;
  codigoBarras: string;
  localizacao: string;
  plataforma: string;
  quantidadeAlvo: number;
  quantidadeLida: number;
  estado: PickingTaskStatus;
}

export interface MissionSummary {
  codigo: string;
  totalLinhas: number;
  linhasConcluidas: number;
}

export const pickingApi = {
  getMission: (): Promise<MissionSummary> => apiFetch<MissionSummary>("/api/picking/mission"),
  listTasks: (): Promise<PickingTask[]> => apiFetch<PickingTask[]>("/api/picking/tasks"),
};
