import { apiFetch } from "./http";

export interface Plataforma {
  id: string;
  codigo: string;
  ordemPreparacaoId: string | null;
  cliente: string | null;
  tipoPlataformaCodigo: string;
  indiceCamada: number | null;
  classeCamada: string | null;
  celulaDestino: string | null;
  estado: string;
  missaoId: string | null;
}

export const plataformasApi = {
  listar: (): Promise<Plataforma[]> => apiFetch<Plataforma[]>("/api/plataformas"),

  // RF-CTL-06: atribui célula e gera a missão de picking (RF-PIC-01).
  despachar: (id: string, celulaDestino: string | null): Promise<{ missaoId: string }> =>
    apiFetch<{ missaoId: string }>(`/api/plataformas/${id}/despachar`, {
      method: "POST",
      body: JSON.stringify({ celulaDestino }),
    }),
};
