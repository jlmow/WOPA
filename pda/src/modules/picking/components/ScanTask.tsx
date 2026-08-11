import { useEffect, useRef, useState } from "react";
import type { PickingTask } from "../types";
import { allowKeyboardOnTap, suppressKeyboardOnBlur } from "../../../shared/scannerInput";

interface Props {
  task: PickingTask;
  onScan: (barcode: string) => Promise<{ ok: true } | { ok: false; erro: string }>;
  onVerLista: () => void;
}

export function ScanTask({ task, onScan, onVerLista }: Props) {
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
          inputMode="none"
          value={barcode}
          onChange={(e) => setBarcode(e.target.value)}
          onPointerDown={allowKeyboardOnTap}
          onBlur={suppressKeyboardOnBlur}
          onClick={() => setBarcode("")}
          placeholder="Ler código de barras"
          disabled={busy}
          autoComplete="off"
        />
        <button type="submit" disabled={busy || !barcode.trim()}>
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
