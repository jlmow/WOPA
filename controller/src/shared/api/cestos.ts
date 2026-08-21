import { apiFetch } from "./http";

export interface CestoInstancia {
  id: string;
  matricula: string;
  tipoCestoCodigo: string;
  estado: "Livre" | "EmUso";
  localizacaoCodigo: string | null;
}

// Registo de cestos físicos (ADR-030/035) — pré-carregados aqui, não
// inventados ao ler no pda (gate de montagem recusa matrícula desconhecida).
export const cestosApi = {
  listar: (): Promise<CestoInstancia[]> => apiFetch<CestoInstancia[]>("/api/cestos-instancias"),
  criar: (matricula: string): Promise<CestoInstancia> =>
    apiFetch<CestoInstancia>("/api/cestos-instancias", { method: "POST", body: JSON.stringify({ matricula }) }),
};
