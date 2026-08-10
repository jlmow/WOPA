import { apiFetch } from "./http";

export interface Modulo {
  slug: string;
  nome: string;
  disponivel: boolean;
}

export const modulosApi = {
  list: (): Promise<Modulo[]> => apiFetch<Modulo[]>("/api/modulos"),
};
