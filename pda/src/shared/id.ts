// crypto.randomUUID() só existe em "contextos seguros" (HTTPS ou
// localhost) -- o pda corre em HTTP simples sobre o IP interno do
// cliente (sem certificado disponível nessa rede, ver ARCHITECTURE.md
// ADR-023), onde o browser esconde randomUUID mas mantém
// getRandomValues. Isto gera operacaoId (ADR-007) para identificar
// operações localmente, não precisa de ser criptograficamente forte --
// só de não colidir na prática.
export function gerarOperacaoId(): string {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }

  if (typeof crypto !== "undefined" && typeof crypto.getRandomValues === "function") {
    const bytes = crypto.getRandomValues(new Uint8Array(16));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  }

  return `${Date.now().toString(16)}-${Math.random().toString(16).slice(2)}-${Math.random().toString(16).slice(2)}`;
}
