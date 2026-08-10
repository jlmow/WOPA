export interface ErrorResponse {
  erro: string;
}

const API_BASE_URL = import.meta.env.VITE_ORCHESTRATOR_URL ?? "http://localhost:5080";

export async function apiFetch<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${API_BASE_URL}${path}`, {
    ...init,
    headers: { "Content-Type": "application/json", ...init?.headers },
  });
  const body = await response.json();
  if (!response.ok) {
    const error = body as ErrorResponse;
    throw new Error(error.erro ?? "Erro desconhecido a comunicar com o orchestrator.");
  }
  return body as T;
}
