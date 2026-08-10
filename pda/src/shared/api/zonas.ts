import { apiFetch } from "./http";

export interface Zona {
  id: string;
  codigo: string;
  nome: string;
}

export const zonasApi = {
  list: (): Promise<Zona[]> => apiFetch<Zona[]>("/api/zonas"),
};
