import Dexie, { type Table } from "dexie";
import type { PickingTask } from "./types";

export interface OutboxEntry {
  opId: string;
  tipo: "scan" | "pick" | "confirm";
  taskId: string;
  barcode?: string;
  alveoloId?: string;
  matriculaPalete?: string;
  quantidade?: number;
  motivo?: string;
  criadoEm: number;
}

export interface MetaEntry {
  chave: string;
  valor: string;
}

// Base de dados local no dispositivo (ADR-007) — é a fonte de verdade do
// ecrã. A rede só serve para manter isto sincronizado com o orchestrator,
// nunca é uma condição para o operador conseguir trabalhar.
class PickingDb extends Dexie {
  tasks!: Table<PickingTask, string>;
  outbox!: Table<OutboxEntry, string>;
  meta!: Table<MetaEntry, string>;

  constructor() {
    super("wopa-pda-picking");
    this.version(1).stores({
      tasks: "id",
      outbox: "opId, criadoEm",
      meta: "chave",
    });
  }
}

export const db = new PickingDb();
