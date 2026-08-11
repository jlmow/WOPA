import { useEffect, useRef, useState } from "react";
import type { MontagemInfo } from "../types";

interface Props {
  montagem: MontagemInfo;
  onConfirmar: (matriculaPalete: string, matriculasCestos: string[]) => Promise<{ ok: true } | { ok: false; erro: string }>;
}

/**
 * Gate de montagem (ADR-029): sem plataforma indicada não há picking de
 * artigos. Na primeira zona de uma Ordem, o operador monta a plataforma
 * de raiz (palete vazia + N cestos vazios, N conforme o tipo — 0 para
 * P0). Nas zonas seguintes, a plataforma já vem montada — só é preciso
 * confirmar a mesma palete e os mesmos cestos, sem os reler do zero.
 */
export function MontarPlataforma({ montagem, onConfirmar }: Props) {
  const [matriculaPalete, setMatriculaPalete] = useState<string | null>(null);
  const [paleteInput, setPaleteInput] = useState("");
  const [cestos, setCestos] = useState<string[]>([]);
  const [cestoInput, setCestoInput] = useState("");
  const [erro, setErro] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    inputRef.current?.focus();
  }, [matriculaPalete, cestos.length]);

  const faltamCestos = montagem.cestosNecessarios - cestos.length;
  const pronto = matriculaPalete !== null && faltamCestos <= 0;

  function lerPalete(e: React.FormEvent) {
    e.preventDefault();
    if (!paleteInput.trim()) return;
    setMatriculaPalete(paleteInput.trim());
    setPaleteInput("");
    setErro(null);
  }

  function lerCesto(e: React.FormEvent) {
    e.preventDefault();
    const codigo = cestoInput.trim();
    if (!codigo || faltamCestos <= 0) return;
    if (cestos.includes(codigo)) {
      setErro("Este cesto já foi lido — os cestos têm de ter matrículas diferentes.");
      setCestoInput("");
      return;
    }
    setCestos((prev) => [...prev, codigo]);
    setCestoInput("");
    setErro(null);
  }

  async function confirmar() {
    if (!pronto || matriculaPalete === null || busy) return;
    setBusy(true);
    const resultado = await onConfirmar(matriculaPalete, cestos);
    setBusy(false);
    if (!resultado.ok) setErro(resultado.erro);
  }

  const titulo = montagem.primeiraMontagem ? "Montar plataforma" : "Confirmar plataforma";

  return (
    <div className="scan-screen" data-testid="montar-plataforma">
      <h2>{titulo}</h2>
      <p className="scan-screen__meta">
        Tipo <strong>{montagem.tipoPlataformaCodigo}</strong>
        {montagem.cestosNecessarios > 0 && ` · ${montagem.cestosNecessarios} cesto(s)`}
      </p>
      {!montagem.primeiraMontagem && (
        <p className="scan-screen__meta">
          Esta plataforma já vem montada de outra zona — confirma a palete
          {montagem.cestosNecessarios > 0 ? " e os cestos" : ""}.
        </p>
      )}

      {matriculaPalete === null && (
        <form onSubmit={lerPalete}>
          <label htmlFor="palete-input">Ler matrícula da palete</label>
          <input
            id="palete-input"
            ref={inputRef}
            data-testid="palete-input"
            value={paleteInput}
            onChange={(e) => setPaleteInput(e.target.value)}
            placeholder="Ler código da palete"
            autoComplete="off"
          />
          <button type="submit" disabled={!paleteInput.trim()}>
            Registar palete
          </button>
        </form>
      )}

      {matriculaPalete !== null && (
        <>
          <div className="platform-badge" data-testid="palete-lida">
            Palete <strong>{matriculaPalete}</strong>
          </div>

          {cestos.length > 0 && (
            <ul className="option-list" data-testid="cestos-lidos">
              {cestos.map((codigo, indice) => (
                <li key={`${codigo}-${indice}`}>
                  <span className="option-card">{codigo}</span>
                </li>
              ))}
            </ul>
          )}

          {faltamCestos > 0 && (
            <form onSubmit={lerCesto}>
              <label htmlFor="cesto-input">
                Ler cesto ({cestos.length}/{montagem.cestosNecessarios})
              </label>
              <input
                id="cesto-input"
                ref={inputRef}
                data-testid="cesto-input"
                value={cestoInput}
                onChange={(e) => setCestoInput(e.target.value)}
                placeholder="Ler código do cesto"
                autoComplete="off"
              />
              <button type="submit" disabled={!cestoInput.trim()}>
                Registar cesto
              </button>
            </form>
          )}

          {pronto && (
            <button className="confirm-button" onClick={confirmar} disabled={busy} data-testid="confirmar-montagem">
              {montagem.primeiraMontagem ? "Confirmar montagem" : "Confirmar plataforma"}
            </button>
          )}
        </>
      )}

      {erro && (
        <p className="scan-screen__message scan-screen__message--erro" data-testid="montagem-erro">
          {erro}
        </p>
      )}
    </div>
  );
}
