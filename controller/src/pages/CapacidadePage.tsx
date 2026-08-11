import { useEffect, useState } from "react";
import { celulasApi, type CargaCelula } from "../shared/api/celulas";

function paraDataInput(d: Date): string {
  return d.toISOString().slice(0, 10);
}

/**
 * Painel de capacidade por célula e por dia (ADR-027) — o requisito-chave
 * saído da reunião de planeamento: o supervisor precisa de ver, por
 * célula, quanto já está comprometido vs. quanto cabe num dia, antes de
 * despachar mais trabalho para lá.
 */
export function CapacidadePage() {
  const [data, setData] = useState(paraDataInput(new Date()));
  const [cargas, setCargas] = useState<CargaCelula[]>([]);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    celulasApi
      .carga(data)
      .then(setCargas)
      .catch((err) => setErro((err as Error).message));
  }, [data]);

  return (
    <div className="page">
      <header className="page__header">
        <h1>Capacidade</h1>
        <p className="page__subtitle">
          Carga vs. capacidade por célula e por dia — despacho com data (RF-CTL-06). "Unidades" é uma métrica
          simples e provisória (soma da quantidade das linhas), por afinar com histórico real.
        </p>
      </header>

      {erro && <p className="page__error">{erro}</p>}

      <div className="form-row">
        <label>
          Dia
          <input type="date" value={data} onChange={(e) => setData(e.target.value)} data-testid="capacidade-data" />
        </label>
      </div>

      <div className="stat-grid" data-testid="capacidade-grid">
        {cargas.map((c) => {
          const pct = c.capacidadeDiariaUnidades > 0 ? Math.round((c.cargaUnidades / c.capacidadeDiariaUnidades) * 100) : 0;
          const saturada = pct >= 100;
          return (
            <div key={c.celulaId} className={`stat-card${saturada ? " stat-card--destaque" : ""}`} data-testid={`carga-${c.celulaId}`}>
              <p className="stat-card__valor">
                {c.cargaUnidades} / {c.capacidadeDiariaUnidades}
              </p>
              <p className="stat-card__label">
                {c.nome} · {pct}%{saturada ? " · saturada" : ""}
              </p>
            </div>
          );
        })}
      </div>

      {cargas.length === 0 && !erro && <p className="page__empty">Sem células configuradas.</p>}
    </div>
  );
}
