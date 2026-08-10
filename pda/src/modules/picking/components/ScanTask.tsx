import { useEffect, useRef, useState } from "react";
import type { PickingTask } from "../types";

interface Props {
  task: PickingTask;
  onScan: (barcode: string) => Promise<{ ok: true } | { ok: false; erro: string }>;
  onCompleted: (taskId: string) => void;
  onVerLista: () => void;
}

const ADVANCE_DELAY_MS = 600;

export function ScanTask({ task, onScan, onCompleted, onVerLista }: Props) {
  const [barcode, setBarcode] = useState("");
  const [message, setMessage] = useState<{ text: string; kind: "erro" | "info" } | null>(null);
  const [busy, setBusy] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  // O leitor físico do PDA funciona como um teclado (keyboard wedge):
  // escreve os dígitos e envia Enter. Manter o foco aqui garante que a
  // leitura cai sempre neste campo, sem o operador ter de tocar no ecrã.
  useEffect(() => {
    setMessage(null);
    setBusy(false);
    inputRef.current?.focus();
  }, [task.id]);

  const completo = task.quantidadeLida >= task.quantidadeAlvo;

  // A leitura é validada e aplicada localmente (ADR-007) — não há chamada de
  // rede a aguardar aqui, por isso o ecrã reage sempre na hora, com ou sem
  // ligação. Quando a linha fica concluída, avança sozinho para a seguinte.
  useEffect(() => {
    if (task.estado !== "Concluida") return;
    setMessage({ text: "Linha concluída. A avançar…", kind: "info" });
    const temporizador = window.setTimeout(() => onCompleted(task.id), ADVANCE_DELAY_MS);
    return () => window.clearTimeout(temporizador);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [task.estado, task.id]);

  async function handleScan(e: React.FormEvent) {
    e.preventDefault();
    if (!barcode.trim() || busy) return;
    const code = barcode.trim();
    setBarcode("");
    setBusy(true);
    const resultado = await onScan(code);
    if (!resultado.ok) {
      setMessage({ text: resultado.erro, kind: "erro" });
    } else {
      setMessage(null);
    }
    setBusy(false);
    inputRef.current?.focus();
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
    </div>
  );
}
