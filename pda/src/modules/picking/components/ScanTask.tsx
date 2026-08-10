import { useEffect, useRef, useState } from "react";
import type { PickingTask } from "../types";
import { pickingApi } from "../api";

interface Props {
  task: PickingTask;
  onUpdated: (task: PickingTask) => void;
  onCompleted: (taskId: string) => void;
  onVerLista: () => void;
}

const ADVANCE_DELAY_MS = 600;

export function ScanTask({ task, onUpdated, onCompleted, onVerLista }: Props) {
  const [barcode, setBarcode] = useState("");
  const [message, setMessage] = useState<{ text: string; kind: "erro" | "info" } | null>(null);
  const [busy, setBusy] = useState(false);
  const [confirmFailed, setConfirmFailed] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  // O leitor físico do PDA funciona como um teclado (keyboard wedge):
  // escreve os dígitos e envia Enter. Manter o foco aqui garante que a
  // leitura cai sempre neste campo, sem o operador ter de tocar no ecrã.
  useEffect(() => {
    setConfirmFailed(false);
    setMessage(null);
    setBusy(false);
    inputRef.current?.focus();
  }, [task.id]);

  const completo = task.quantidadeLida >= task.quantidadeAlvo;

  // Uma leitura que atinge a quantidade alvo já é, por si só, a confirmação
  // do operador — não faz sentido pedir mais um toque para confirmar algo
  // que a própria leitura já provou. O sistema confirma e avança sozinho
  // para a linha seguinte da missão.
  async function confirmAndAdvance() {
    try {
      const confirmed = await pickingApi.confirm(task.id);
      onUpdated(confirmed);
      setMessage({ text: "Linha concluída. A avançar…", kind: "info" });
      window.setTimeout(() => onCompleted(task.id), ADVANCE_DELAY_MS);
    } catch (err) {
      setConfirmFailed(true);
      setMessage({ text: (err as Error).message, kind: "erro" });
      setBusy(false);
    }
  }

  async function handleScan(e: React.FormEvent) {
    e.preventDefault();
    if (!barcode.trim() || busy) return;
    const code = barcode.trim();
    setBarcode("");
    setBusy(true);
    try {
      const updated = await pickingApi.scan(task.id, code);
      onUpdated(updated);
      if (updated.quantidadeLida >= updated.quantidadeAlvo) {
        // Continua "busy" (ecrã bloqueado) até o avanço automático ocorrer.
        await confirmAndAdvance();
        return;
      }
      setMessage(null);
      setBusy(false);
      inputRef.current?.focus();
    } catch (err) {
      setMessage({ text: (err as Error).message, kind: "erro" });
      setBusy(false);
      inputRef.current?.focus();
    }
  }

  return (
    <div className="scan-screen">
      <button className="link-button" onClick={onVerLista} data-testid="ver-lista-button">
        Ver lista da missão
      </button>

      <h2>{task.descricao}</h2>
      <p className="scan-screen__meta">
        SKU {task.sku} · Localização <strong>{task.localizacao}</strong>
      </p>

      <div className="platform-badge" data-testid="plataforma">
        Colocar em <strong>{task.plataforma}</strong>
      </div>

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

      {confirmFailed && (
        <button
          className="confirm-button"
          onClick={() => {
            setBusy(true);
            confirmAndAdvance();
          }}
          data-testid="retry-confirm-button"
        >
          Tentar confirmar novamente
        </button>
      )}
    </div>
  );
}
