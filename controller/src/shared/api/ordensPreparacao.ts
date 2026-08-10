import { apiFetch } from "./http";

export interface PlataformaResumo {
  id: string;
  codigo: string;
  tipoPlataformaCodigo: string;
  indiceCamada: number | null;
  classeCamada: string | null;
  estado: string;
  celulaDestino: string | null;
}

export interface OrdemPreparacaoResumo {
  id: string;
  cliente: string;
  dataEntrega: string | null;
  moradaEntrega: string | null;
  estado: "Aberta" | "Tipificada" | "Despachada";
  alturaPaleteCm: number | null;
  criadaEm: string;
  nPs: number;
  volumeLitros: number | null;
  pesoKg: number | null;
  tipoIndicativo: string | null;
  plataformas: PlataformaResumo[];
}

export interface NovaOrdemPreparacaoRequest {
  cliente: string;
  dataEntrega: string | null;
  moradaEntrega: string | null;
  psIds: string[];
}

export const ordensPreparacaoApi = {
  listar: (): Promise<OrdemPreparacaoResumo[]> => apiFetch<OrdemPreparacaoResumo[]>("/api/ordens-preparacao"),

  compor: (pedido: NovaOrdemPreparacaoRequest): Promise<OrdemPreparacaoResumo> =>
    apiFetch<OrdemPreparacaoResumo>("/api/ordens-preparacao", {
      method: "POST",
      body: JSON.stringify(pedido),
    }),

  // Anexo A.4/A.5/A.8 — cubica, tipifica e gera as Plataformas.
  tipificar: (id: string, alturaPaleteCm: number | null): Promise<OrdemPreparacaoResumo> =>
    apiFetch<OrdemPreparacaoResumo>(`/api/ordens-preparacao/${id}/tipificar`, {
      method: "POST",
      body: JSON.stringify({ alturaPaleteCm }),
    }),
};
