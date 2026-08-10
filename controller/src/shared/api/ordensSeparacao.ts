import { apiFetch } from "./http";

export interface OrdemSeparacaoLinha {
  sku: string;
  quantidade: number;
  alveoloCodigo: string | null;
}

export interface CubicagemIndicativa {
  volumeLitros: number;
  pesoKg: number;
  nRefs: number;
  nLinhasNaoCubicaveis: number;
  tipoIndicativo: string | null;
}

export interface OrdemSeparacao {
  id: string;
  numeroDocumento: string;
  origem: string;
  recebidaEm: string;
  processada: boolean;
  cliente: string | null;
  dataEntrega: string | null;
  moradaEntrega: string | null;
  canal: string | null;
  ordemPreparacaoId: string | null;
  linhas: OrdemSeparacaoLinha[];
  cubicagem: CubicagemIndicativa | null;
}

export const ordensSeparacaoApi = {
  // RF-CTL-01: PS ainda não agrupados numa Ordem de Preparação.
  listarAbertas: (): Promise<OrdemSeparacao[]> => apiFetch<OrdemSeparacao[]>("/api/ordens-separacao?abertas=true"),
};
