export type PickingTaskStatus = "Pendente" | "EmProgresso" | "Concluida";

export interface PickingTask {
  id: string;
  sku: string;
  descricao: string;
  codigoBarras: string;
  localizacao: string;
  quantidadeAlvo: number;
  quantidadeLida: number;
  estado: PickingTaskStatus;
}

export interface ErrorResponse {
  erro: string;
}
