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

export interface AlveoloComStock {
  alveoloId: string;
  codigo: string;
  quantidadeDisponivel: number;
  sugestaoQuantidade: number;
}
