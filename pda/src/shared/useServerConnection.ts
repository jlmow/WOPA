import { useEffect, useState } from "react";

const HEALTH_CHECK_INTERVAL_MS = 8000;
const HEALTH_CHECK_TIMEOUT_MS = 3000;
const API_BASE_URL = import.meta.env.VITE_ORCHESTRATOR_URL ?? "http://localhost:5080";

/**
 * ADR-009: navigator.onLine só diz se o sistema operativo tem uma interface
 * de rede ativa — não garante que o orchestrator está mesmo alcançável (pode
 * haver Wi-Fi mas o servidor em baixo, ou numa VLAN sem rota até lá). Este
 * hook confirma com um pedido real e periódico a /health.
 */
export function useServerConnection(): boolean {
  const [ligado, setLigado] = useState(false);

  useEffect(() => {
    let cancelado = false;

    async function verificar() {
      if (!navigator.onLine) {
        if (!cancelado) setLigado(false);
        return;
      }
      try {
        const controller = new AbortController();
        const temporizador = window.setTimeout(() => controller.abort(), HEALTH_CHECK_TIMEOUT_MS);
        const resposta = await fetch(`${API_BASE_URL}/health`, { signal: controller.signal });
        window.clearTimeout(temporizador);
        if (!cancelado) setLigado(resposta.ok);
      } catch {
        if (!cancelado) setLigado(false);
      }
    }

    verificar();
    const intervalo = window.setInterval(verificar, HEALTH_CHECK_INTERVAL_MS);
    window.addEventListener("online", verificar);
    window.addEventListener("offline", verificar);

    return () => {
      cancelado = true;
      window.clearInterval(intervalo);
      window.removeEventListener("online", verificar);
      window.removeEventListener("offline", verificar);
    };
  }, []);

  return ligado;
}
