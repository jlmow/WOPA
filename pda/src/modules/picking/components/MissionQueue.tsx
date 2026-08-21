import { useEffect, useState } from "react";
import type { MissaoResumo } from "../types";
import { pickingApi } from "../api";

interface Props {
  onFechar: () => void;
}

/**
 * Fila de missões só de consulta (ADR-037) — "uma missão de cada vez"
 * (ADR-008) continua a valer, o operador não escolhe nem salta à frente
 * aqui, só vê o que tem a seguir. Por isso os cartões não são botões.
 */
export function MissionQueue({ onFechar }: Props) {
  const [missoes, setMissoes] = useState<MissaoResumo[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    let cancelado = false;
    pickingApi
      .listMissions()
      .then((lista) => {
        if (!cancelado) setMissoes(lista);
      })
      .catch((err) => {
        if (!cancelado) setErro((err as Error).message || "Não foi possível obter a fila de missões.");
      });
    return () => {
      cancelado = true;
    };
  }, []);

  return (
    <div className="scan-screen" data-testid="mission-queue">
      <button className="link-button" onClick={onFechar} data-testid="fechar-missoes">
        &larr; Voltar
      </button>

      <h2>Fila de missões</h2>
      <p className="scan-screen__meta">Só de consulta — a ordem é sempre a mais antiga primeiro (ADR-008).</p>

      {erro && <p className="scan-screen__message scan-screen__message--erro">{erro}</p>}

      {!erro && missoes === null && <p>A obter missões…</p>}

      {missoes && missoes.length === 0 && <p className="scan-screen__message scan-screen__message--info">Sem missões na fila.</p>}

      {missoes && missoes.length > 0 && (
        <ul className="option-list" data-testid="mission-queue-list">
          {missoes.map((m) => (
            <li key={m.id}>
              <div
                className={`option-card${m.atual ? " option-card--selecionado" : ""}`}
                data-testid={`missao-fila-${m.id}`}
              >
                <span className="option-card__codigo">{m.codigo}</span>
                <span className="option-card__nome">
                  {m.linhasConcluidas}/{m.totalLinhas} linhas
                </span>
                {m.atual && <span className="mission-queue__badge">Atual</span>}
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
