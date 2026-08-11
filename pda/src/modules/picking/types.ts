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

// Gate de montagem (ADR-029): primeiraMontagem=true -> esta zona monta a
// plataforma de raiz (palete + N cestos vazios); false -> já vem montada
// de outra zona, só é preciso confirmar (mesma palete + mesmos cestos).
export interface MontagemInfo {
  plataformaId: string;
  tipoPlataformaCodigo: string;
  cestosNecessarios: number;
  confirmada: boolean;
  primeiraMontagem: boolean;
}

export interface MissionSummary {
  id: string;
  codigo: string;
  totalLinhas: number;
  linhasConcluidas: number;
  montagem: MontagemInfo | null;
}

export interface AlveoloComStock {
  alveoloId: string;
  codigo: string;
  quantidadeDisponivel: number;
  sugestaoQuantidade: number;
}
