import { apiFetch } from "./http";

export interface Celula {
  id: string;
  codigo: string;
  nome: string;
  capacidadeDiariaUnidades: number;
  ativa: boolean;
}

export interface CargaCelula {
  celulaId: string;
  codigo: string;
  nome: string;
  capacidadeDiariaUnidades: number;
  cargaUnidades: number;
}

export const celulasApi = {
  listar: (): Promise<Celula[]> => apiFetch<Celula[]>("/api/celulas"),

  // Carga vs. capacidade por dia (ADR-027) — "unidades" é uma métrica
  // simples e provisória (soma de QuantidadeAlvo), por afinar com
  // histórico real ao fim de alguns meses.
  carga: (data: string): Promise<CargaCelula[]> => apiFetch<CargaCelula[]>(`/api/celulas/carga?data=${data}`),
};
