import { useEffect, useState } from "react";
import { ordensPreparacaoApi, type OrdemPreparacaoResumo } from "../shared/api/ordensPreparacao";
import { plataformasApi, type Plataforma } from "../shared/api/plataformas";
import { celulasApi, type Celula } from "../shared/api/celulas";

const ESTADO_LABEL: Record<OrdemPreparacaoResumo["estado"], string> = {
  Aberta: "Aberta",
  Tipificada: "Tipificada",
  Despachada: "Despachada",
};

function hoje(): string {
  return new Date().toISOString().slice(0, 10);
}

export function OrdensPreparacaoPage() {
  const [ordens, setOrdens] = useState<OrdemPreparacaoResumo[]>([]);
  const [plataformas, setPlataformas] = useState<Record<string, Plataforma>>({});
  const [celulas, setCelulas] = useState<Celula[]>([]);
  const [erro, setErro] = useState<string | null>(null);
  const [alturaPorOrdem, setAlturaPorOrdem] = useState<Record<string, string>>({});
  const [celulaPorPlataforma, setCelulaPorPlataforma] = useState<Record<string, string>>({});
  const [dataPorPlataforma, setDataPorPlataforma] = useState<Record<string, string>>({});
  const [aProcessar, setAProcessar] = useState<string | null>(null);

  function carregar() {
    Promise.all([ordensPreparacaoApi.listar(), plataformasApi.listar(), celulasApi.listar()])
      .then(([listaOrdens, listaPlataformas, listaCelulas]) => {
        // Urgentes primeiro (ADR-027) -- fila com prioridade, sem ainda ser
        // arrastar-para-reordenar (fica em aberto, ver ARCHITECTURE.md).
        setOrdens([...listaOrdens].sort((a, b) => Number(b.urgente) - Number(a.urgente)));
        setPlataformas(Object.fromEntries(listaPlataformas.map((p) => [p.id, p])));
        setCelulas(listaCelulas);
      })
      .catch((err) => setErro((err as Error).message));
  }

  useEffect(carregar, []);

  const abertas = ordens.filter((o) => o.estado === "Aberta").length;
  const tipificadas = ordens.filter((o) => o.estado === "Tipificada").length;
  const despachadas = ordens.filter((o) => o.estado === "Despachada").length;

  async function tipificar(id: string) {
    setAProcessar(id);
    setErro(null);
    try {
      const altura = alturaPorOrdem[id];
      await ordensPreparacaoApi.tipificar(id, altura ? Number(altura) : null);
      carregar();
    } catch (err) {
      setErro((err as Error).message);
    } finally {
      setAProcessar(null);
    }
  }

  async function alternarUrgente(ordem: OrdemPreparacaoResumo) {
    setErro(null);
    try {
      await ordensPreparacaoApi.marcarUrgente(ordem.id, !ordem.urgente, ordem.dataLimite);
      carregar();
    } catch (err) {
      setErro((err as Error).message);
    }
  }

  async function despachar(plataformaId: string) {
    setAProcessar(plataformaId);
    setErro(null);
    try {
      await plataformasApi.despachar(
        plataformaId,
        celulaPorPlataforma[plataformaId] || null,
        celulaPorPlataforma[plataformaId] || null,
        dataPorPlataforma[plataformaId] || null,
      );
      carregar();
    } catch (err) {
      setErro((err as Error).message);
    } finally {
      setAProcessar(null);
    }
  }

  return (
    <div className="page">
      <header className="page__header">
        <h1>Ordens de Preparação</h1>
        <p className="page__subtitle">
          Recebidas já compostas de outro software. Cubicagem, tipificação (P4/P2/P1/P1(n)) e despacho de
          plataformas para picking (RF-CTL-01/05/06).
        </p>
      </header>

      {erro && <p className="page__error">{erro}</p>}

      <div className="stat-grid" data-testid="ordens-stats">
        <div className="stat-card stat-card--destaque">
          <p className="stat-card__valor">{abertas}</p>
          <p className="stat-card__label">Abertas</p>
        </div>
        <div className="stat-card">
          <p className="stat-card__valor">{tipificadas}</p>
          <p className="stat-card__label">Tipificadas</p>
        </div>
        <div className="stat-card">
          <p className="stat-card__valor">{despachadas}</p>
          <p className="stat-card__label">Despachadas</p>
        </div>
        <div className="stat-card">
          <p className="stat-card__valor">{ordens.length}</p>
          <p className="stat-card__label">Total</p>
        </div>
      </div>

      {ordens.map((ordem) => (
        <section
          key={ordem.id}
          className={`panel${ordem.urgente ? " panel--destaque" : ""}`}
          data-testid={`op-${ordem.id}`}
        >
          <div className="panel__header-row">
            <div>
              <h2>
                {ordem.urgente && <span className="status-tag status-tag--erro">Urgente</span>} {ordem.cliente}
              </h2>
              <p className="page__subtitle">
                {ordem.nPs} PS · {ordem.moradaEntrega ?? "sem morada"} · entrega {ordem.dataEntrega ?? "—"}
                {ordem.dataLimite && <> · limite {new Date(ordem.dataLimite).toLocaleString("pt-PT")}</>}
              </p>
            </div>
            <div className="acoes-cell">
              <button
                className={`button button--small${ordem.urgente ? " button--primary" : ""}`}
                onClick={() => alternarUrgente(ordem)}
                data-testid={`urgente-${ordem.id}`}
              >
                {ordem.urgente ? "Desmarcar urgente" : "Marcar urgente"}
              </button>
              <span className={`status-tag status-tag--op-${ordem.estado}`} data-testid={`op-estado-${ordem.id}`}>
                {ESTADO_LABEL[ordem.estado]}
              </span>
            </div>
          </div>

          <p>
            Volume: <strong>{ordem.volumeLitros?.toFixed(1) ?? "—"} L</strong> · Peso:{" "}
            <strong>{ordem.pesoKg?.toFixed(1) ?? "—"} kg</strong> · Tipo indicativo:{" "}
            <strong>{ordem.tipoIndicativo ?? "—"}</strong>
          </p>

          {ordem.estado === "Aberta" && (
            <div className="tipificar-bloco">
              <p className="tipificar-bloco__explicacao">
                <strong>Tipificar</strong> calcula o volume e o peso desta ordem a partir das linhas dos PS,
                escolhe a plataforma mais pequena onde cabe (P4, P2 ou P1) — ou várias plataformas P1 se
                ultrapassar a maior capacidade — e cria essas plataformas, prontas a despachar para picking.
              </p>
              <div className="form-row">
                <label>
                  Altura da palete final (cm)
                  <input
                    type="number"
                    placeholder="ex. 150"
                    value={alturaPorOrdem[ordem.id] ?? ""}
                    onChange={(e) => setAlturaPorOrdem((prev) => ({ ...prev, [ordem.id]: e.target.value }))}
                    data-testid={`altura-${ordem.id}`}
                  />
                </label>
                <button
                  className="button button--primary"
                  onClick={() => tipificar(ordem.id)}
                  disabled={aProcessar === ordem.id}
                  data-testid={`tipificar-${ordem.id}`}
                >
                  {aProcessar === ordem.id ? "A tipificar…" : "Tipificar"}
                </button>
              </div>
              <p className="tipificar-bloco__aviso">
                Opcional — só importa quando esta ordem gera <strong>mais que uma plataforma</strong>: define
                quantas plataformas empilhar antes de repetir o padrão pesado/leve. Regra ainda provisória
                (limiar 140 cm), por confirmar com o cliente — deixa em branco se não souberes.
              </p>
            </div>
          )}

          {ordem.plataformas.length > 0 && (
            <table className="data-table" data-testid={`plataformas-${ordem.id}`}>
              <thead>
                <tr>
                  <th>Plataforma</th>
                  <th>Tipo</th>
                  <th>Camada</th>
                  <th>Célula</th>
                  <th>Dia</th>
                  <th>Estado</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {ordem.plataformas.map((plat) => {
                  const despachada = plataformas[plat.id]?.missaoId != null;
                  return (
                    <tr key={plat.id} data-testid={`plataforma-${plat.id}`}>
                      <td>{plat.codigo}</td>
                      <td>{plat.tipoPlataformaCodigo}</td>
                      <td>
                        {plat.indiceCamada ? `${plat.indiceCamada} · ${plat.classeCamada}` : "—"}
                      </td>
                      <td>
                        {despachada ? (
                          plat.celulaDestino ?? "—"
                        ) : (
                          <select
                            value={celulaPorPlataforma[plat.id] ?? ""}
                            onChange={(e) => setCelulaPorPlataforma((prev) => ({ ...prev, [plat.id]: e.target.value }))}
                            data-testid={`celula-${plat.id}`}
                          >
                            <option value="">Escolher célula…</option>
                            {celulas.map((c) => (
                              <option key={c.id} value={c.id}>
                                {c.nome}
                              </option>
                            ))}
                          </select>
                        )}
                      </td>
                      <td>
                        {!despachada && (
                          <input
                            type="date"
                            min={hoje()}
                            value={dataPorPlataforma[plat.id] ?? ""}
                            onChange={(e) => setDataPorPlataforma((prev) => ({ ...prev, [plat.id]: e.target.value }))}
                            data-testid={`data-despacho-${plat.id}`}
                          />
                        )}
                      </td>
                      <td>
                        <span className={`status-tag status-tag--plat-${plat.estado}`}>{plat.estado}</span>
                      </td>
                      <td>
                        {!despachada && (
                          <button
                            className="button button--small"
                            onClick={() => despachar(plat.id)}
                            disabled={aProcessar === plat.id}
                            data-testid={`despachar-${plat.id}`}
                          >
                            {aProcessar === plat.id ? "A despachar…" : "Despachar"}
                          </button>
                        )}
                        {despachada && <span className="status-tag status-tag--Concluida">Em missão</span>}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </section>
      ))}

      {ordens.length === 0 && !erro && <p className="page__empty">Sem Ordens de Preparação recebidas.</p>}
    </div>
  );
}
