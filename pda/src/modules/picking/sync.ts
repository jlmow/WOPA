import { db } from "./db";
import { pickingApi } from "./api";
import type { PickingTask } from "./types";

/**
 * Drena a fila de saída pela ordem em que foi criada, enviando cada
 * operação ao orchestrator. Uma falha de rede (offline) para a fila onde
 * está — tenta-se outra vez mais tarde, sem perder a ordem. Uma falha de
 * negócio (ex.: missão cancelada) descarta essa entrada isolada — ver
 * limitações do ADR-007.
 */
export async function flushOutbox(onSincronizado?: (taskId: string, atualizado: PickingTask) => void): Promise<void> {
  if (!navigator.onLine) return;

  const pendentes = await db.outbox.orderBy("criadoEm").toArray();
  for (const entrada of pendentes) {
    try {
      const atualizado =
        entrada.tipo === "scan"
          ? await pickingApi.scan(entrada.taskId, entrada.barcode!, entrada.opId)
          : entrada.tipo === "pick"
            ? await pickingApi.pick(entrada.taskId, entrada.alveoloId!, entrada.quantidade!, entrada.motivo, entrada.opId)
            : await pickingApi.confirm(entrada.taskId, entrada.opId);

      await db.tasks.put(atualizado);
      await db.outbox.delete(entrada.opId);
      onSincronizado?.(entrada.taskId, atualizado);
    } catch (err) {
      if (err instanceof TypeError) {
        // Falha de rede genuína (fetch nem chegou a responder) — para aqui,
        // preserva a ordem, tenta-se de novo no próximo flush.
        return;
      }
      // Erro de negócio devolvido pelo servidor (ex.: 409). Já validámos
      // localmente antes de enfileirar, por isso isto deve ser raro — mas
      // se acontecer, não bloqueia o resto da fila.
      console.warn(`Falha ao sincronizar operação ${entrada.opId} (${entrada.tipo}):`, err);
      await db.outbox.delete(entrada.opId);
    }
  }
}
