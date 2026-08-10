import { useEffect, useRef, useState } from "react";
import type { PickingTask } from "../types";
import { pickingApi } from "../api";

interface Props {
  task: PickingTask;
  onUpdated: (task: PickingTask) => void;
  onBack: () => void;
}

export function ScanTask({ task, onUpdated, onBack }: Props) {
  const [barcode, setBarcode] = useState("");
  const [message, setMessage] = useState<{ text: string; kind: "erro" | "info" } | null>(null);
  const [busy, setBusy] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  // O leitor físico do PDA funciona como um teclado (keyboard wedge):
  // escreve os dígitos e envia Enter. Manter o foco aqui garante que a
  // leitura cai sempre neste campo, sem o operador ter de tocar no ecrã.
  useEffect(() => {
    inputRef.current?.focus();
  }, [task.id]);

  const completo = task.quantidadeLida >= task.quantidadeAlvo;

  async function handleScan(e: React.FormEvent) {
    e.preventDefault();
    if (!barcode.trim() || busy) return;
    setBusy(true);
    try {
      const updated = await pickingApi.scan(task.id, barcode.trim());
      onUpdated(updated);
      setMessage({ text: "Leitura registada.", kind: "info" });
    } catch (err) {
      setMessage({ text: (err as Error).message, kind: "erro" });
    } finally {
      setBarcode("");
      setBusy(false);
      inputRef.current?.focus();
    }
  }

  async function handleConfirm() {
    setBusy(true);
    try {
      const updated = await pickingApi.confirm(task.id);
      onUpdated(updated);
      setMessage({ text: "Tarefa confirmada.", kind: "info" });
    } catch (err) {
      setMessage({ text: (err as Error).message, kind: "erro" });
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="scan-screen">
      <button className="back-button" onClick={onBack} data-testid="back-button">
        &larr; Voltar
      </button>

      <h2>{task.descricao}</h2>
      <p className="scan-screen__meta">
        SKU {task.sku} · Localização <strong>{task.localizacao}</strong>
      </p>

      <div className="scan-screen__progress" data-testid="progress">
        {task.quantidadeLida} / {task.quantidadeAlvo}
      </div>

      <form onSubmit={handleScan}>
        <input
          ref={inputRef}
          data-testid="barcode-input"
          value={barcode}
          onChange={(e) => setBarcode(e.target.value)}
          placeholder="Ler código de barras"
          disabled={completo || busy}
          autoComplete="off"
        />
        <button type="submit" disabled={completo || busy || !barcode.trim()}>
          Registar leitura
        </button>
      </form>

      {message && (
        <p className={`scan-screen__message scan-screen__message--${message.kind}`} data-testid="message">
          {message.text}
        </p>
      )}

      <button
        className="confirm-button"
        onClick={handleConfirm}
        disabled={!completo || busy || task.estado === "Concluida"}
        data-testid="confirm-button"
      >
        {task.estado === "Concluida" ? "Tarefa concluída" : "Confirmar tarefa"}
      </button>
    </div>
  );
}
