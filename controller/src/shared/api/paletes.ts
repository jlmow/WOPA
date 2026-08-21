import { apiFetch } from "./http";

export interface Palete {
  id: string;
  matricula: string;
  ativa: boolean;
  localizacaoCodigo: string | null;
}

// Registo de paletes (ADR-035) — pré-carregadas aqui, não inventadas ao
// ler no pda (gate de montagem e /pick recusam matrícula desconhecida).
export const paletesApi = {
  listar: (): Promise<Palete[]> => apiFetch<Palete[]>("/api/paletes"),
  criar: (matricula: string): Promise<Palete> =>
    apiFetch<Palete>("/api/paletes", { method: "POST", body: JSON.stringify({ matricula }) }),
};
