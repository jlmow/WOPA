import { apiFetch } from "./http";

export type EstadoMissao = "Criada" | "Atribuida" | "EmExecucao" | "Pausada" | "Concluida" | "FechadaIncompleta";

export interface Missao {
  id: string;
  codigo: string;
  centroTrabalho: string;
  zonaId: string | null;
  plataformaCodigo: string | null;
  utilizadorId: string | null;
  estado: EstadoMissao;
  motivoPausa: string | null;
  criadaEm: string;
  atribuidaEm: string | null;
  iniciadaEm: string | null;
  pausadaEm: string | null;
  concluidaEm: string | null;
  totalLinhas: number;
  linhasConcluidas: number;
}

// A.13 — motivos tipificados de pausa.
export const MOTIVOS_PAUSA = ["Rutura", "FimTurno", "MudancaPrioridade", "Avaria"] as const;

export const missoesApi = {
  listar: (): Promise<Missao[]> => apiFetch<Missao[]>("/api/missoes"),
  pausar: (id: string, motivo: string): Promise<Missao> =>
    apiFetch<Missao>(`/api/missoes/${id}/pausar`, { method: "POST", body: JSON.stringify({ motivo }) }),
  retomar: (id: string): Promise<Missao> => apiFetch<Missao>(`/api/missoes/${id}/retomar`, { method: "POST" }),
  fechar: (id: string): Promise<Missao> => apiFetch<Missao>(`/api/missoes/${id}/fechar`, { method: "POST" }),
  reatribuir: (id: string, utilizadorId: string | null): Promise<Missao> =>
    apiFetch<Missao>(`/api/missoes/${id}/reatribuir`, {
      method: "POST",
      body: JSON.stringify({ utilizadorId, terminalId: null }),
    }),
};
