import { useEffect, useRef, useState } from "react";
import type { PlataformaComposicao } from "../types";
import { pickingApi } from "../api";
import { allowKeyboardOnTap, suppressKeyboardOnBlur } from "../../../shared/scannerInput";
import { gerarOperacaoId } from "../../../shared/id";

interface Props {
  missaoId: string;
  onFechar: () => void;
}

type TrocaAlvo = { tipo: "palete" } | { tipo: "cesto"; matriculaAntiga: string };

/**
 * Composição da plataforma já montada (ADR-036) — o operador confirma o
 * que lá está (palete + cestos) e pode trocar equipamento que se
 * danifique a meio da missão, sem ter de recomeçar a montagem do zero.
 * Sempre em direto (ação rara, feita com o operador parado à espera).
 */
export function ComposicaoPlataforma({ missaoId, onFechar }: Props) {
  const [composicao, setComposicao] = useState<PlataformaComposicao | null>(null);
  const [erroCarregar, setErroCarregar] = useState<string | null>(null);
  const [trocaAlvo, setTrocaAlvo] = useState<TrocaAlvo | null>(null);
  const [novaMatricula, setNovaMatricula] = useState("");
  const [erroTroca, setErroTroca] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    let cancelado = false;
    pickingApi
      .composicaoPlataforma(missaoId)
      .then((c) => {
        if (!cancelado) setComposicao(c);
      })
      .catch((err) => {
        if (!cancelado) setErroCarregar((err as Error).message || "Não foi possível obter a composição.");
      });
    return () => {
      cancelado = true;
    };
  }, [missaoId]);

  useEffect(() => {
    if (trocaAlvo) inputRef.current?.focus();
  }, [trocaAlvo]);

  function iniciarTroca(alvo: TrocaAlvo) {
    setTrocaAlvo(alvo);
    setNovaMatricula("");
    setErroTroca(null);
  }

  async function confirmarTroca(e: React.FormEvent) {
    e.preventDefault();
    if (!trocaAlvo || !novaMatricula.trim() || busy) return;
    setBusy(true);
    setErroTroca(null);
    try {
      const atualizada =
        trocaAlvo.tipo === "palete"
          ? await pickingApi.trocarPalete(missaoId, novaMatricula.trim(), gerarOperacaoId())
          : await pickingApi.trocarCesto(missaoId, trocaAlvo.matriculaAntiga, novaMatricula.trim(), gerarOperacaoId());
      setComposicao(atualizada);
      setTrocaAlvo(null);
      setNovaMatricula("");
    } catch (err) {
      setErroTroca((err as Error).message || "Não foi possível trocar o equipamento.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="scan-screen" data-testid="composicao-plataforma">
      <button className="link-button" onClick={onFechar} data-testid="fechar-composicao">
        &larr; Voltar
      </button>

      <h2>Composição da plataforma</h2>

      {erroCarregar && <p className="scan-screen__message scan-screen__message--erro">{erroCarregar}</p>}

      {!erroCarregar && composicao === null && <p>A obter composição…</p>}

      {composicao && (
        <>
          <p className="scan-screen__meta">
            Plataforma <strong>{composicao.plataformaCodigo}</strong>
          </p>

          <div className="platform-badge" data-testid="palete-composicao">
            Palete <strong>{composicao.paleteMatricula ?? "—"}</strong>
            {trocaAlvo?.tipo !== "palete" && (
              <button
                type="button"
                className="link-button"
                onClick={() => iniciarTroca({ tipo: "palete" })}
                data-testid="trocar-palete-button"
              >
                Trocar (avariada)
              </button>
            )}
          </div>

          {composicao.cestos.length > 0 && (
            <ul className="option-list" data-testid="cestos-composicao">
              {composicao.cestos.map((cesto) => (
                <li key={cesto.matricula}>
                  <span className="option-card">
                    {cesto.matricula} · {cesto.tipoCestoCodigo}
                  </span>
                  {!(trocaAlvo?.tipo === "cesto" && trocaAlvo.matriculaAntiga === cesto.matricula) && (
                    <button
                      type="button"
                      className="link-button"
                      onClick={() => iniciarTroca({ tipo: "cesto", matriculaAntiga: cesto.matricula })}
                      data-testid={`trocar-cesto-${cesto.matricula}`}
                    >
                      Trocar (avariado)
                    </button>
                  )}
                </li>
              ))}
            </ul>
          )}

          {trocaAlvo && (
            <form onSubmit={confirmarTroca}>
              <label htmlFor="nova-matricula">
                {trocaAlvo.tipo === "palete"
                  ? "Ler matrícula da nova palete"
                  : `Ler matrícula do novo cesto (substitui ${trocaAlvo.matriculaAntiga})`}
              </label>
              <input
                id="nova-matricula"
                ref={inputRef}
                data-testid="nova-matricula-input"
                inputMode="none"
                value={novaMatricula}
                onChange={(e) => setNovaMatricula(e.target.value)}
                onPointerDown={allowKeyboardOnTap}
                onBlur={suppressKeyboardOnBlur}
                onClick={() => setNovaMatricula("")}
                placeholder="Ler código"
                autoComplete="off"
                disabled={busy}
              />
              <button type="submit" disabled={!novaMatricula.trim() || busy} data-testid="confirmar-troca">
                Confirmar troca
              </button>
              <button type="button" className="link-button" onClick={() => setTrocaAlvo(null)} disabled={busy}>
                Cancelar
              </button>
              {erroTroca && (
                <p className="scan-screen__message scan-screen__message--erro" data-testid="troca-erro">
                  {erroTroca}
                </p>
              )}
            </form>
          )}
        </>
      )}
    </div>
  );
}
