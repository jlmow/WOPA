import { useEffect, useState } from "react";
import { MOTIVOS_PAUSA, missoesApi, type Missao } from "../shared/api/missoes";

const ESTADO_LABEL: Record<Missao["estado"], string> = {
  Criada: "Criada",
  Atribuida: "Atribuída",
  EmExecucao: "Em execução",
  Pausada: "Pausada",
  Concluida: "Concluída",
  FechadaIncompleta: "Fechada (incompleta)",
};

export function MissoesPage() {
  const [missoes, setMissoes] = useState<Missao[]>([]);
  const [erro, setErro] = useState<string | null>(null);
  const [motivoPorMissao, setMotivoPorMissao] = useState<Record<string, string>>({});
  const [aProcessar, setAProcessar] = useState<string | null>(null);

  function carregar() {
    missoesApi
      .listar()
      .then(setMissoes)
      .catch((err) => setErro((err as Error).message));
  }

  useEffect(carregar, []);

  const emExecucao = missoes.filter((m) => m.estado === "EmExecucao").length;
  const pausadas = missoes.filter((m) => m.estado === "Pausada").length;
  const porAtribuir = missoes.filter((m) => m.estado === "Criada" || m.estado === "Atribuida").length;
  const hoje = new Date().toDateString();
  const concluidasHoje = missoes.filter((m) => m.concluidaEm && new Date(m.concluidaEm).toDateString() === hoje).length;

  async function executar(acao: () => Promise<Missao>, id: string) {
    setAProcessar(id);
    setErro(null);
    try {
      await acao();
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
        <h1>Missões</h1>
        <p className="page__subtitle">
          Fila de trabalho por centro (picking, packing, transporte, abastecimento, reposição, P0) — RF-CTL-09/10.
        </p>
      </header>

      {erro && <p className="page__error">{erro}</p>}

      <div className="stat-grid" data-testid="missoes-stats">
        <div className="stat-card stat-card--destaque">
          <p className="stat-card__valor">{emExecucao}</p>
          <p className="stat-card__label">Em execução</p>
        </div>
        <div className="stat-card">
          <p className="stat-card__valor">{porAtribuir}</p>
          <p className="stat-card__label">Por atribuir</p>
        </div>
        <div className="stat-card">
          <p className="stat-card__valor">{pausadas}</p>
          <p className="stat-card__label">Pausadas</p>
        </div>
        <div className="stat-card">
          <p className="stat-card__valor">{concluidasHoje}</p>
          <p className="stat-card__label">Concluídas hoje</p>
        </div>
      </div>

      <table className="data-table" data-testid="missoes-table">
        <thead>
          <tr>
            <th>Código</th>
            <th>Centro</th>
            <th>Plataforma</th>
            <th>Progresso</th>
            <th>Estado</th>
            <th>Motivo</th>
            <th>Ações</th>
          </tr>
        </thead>
        <tbody>
          {missoes.map((m) => (
            <tr key={m.id} data-testid={`missao-${m.id}`}>
              <td>{m.codigo}</td>
              <td>{m.centroTrabalho}</td>
              <td>
                {m.plataformaCodigo ?? "—"}
                {m.plataformaCodigo && !m.plataformaConfirmada && (
                  <span className="status-tag status-tag--aviso" data-testid={`plataforma-por-montar-${m.id}`}>
                    Por montar
                  </span>
                )}
              </td>
              <td>
                {m.linhasConcluidas}/{m.totalLinhas}
              </td>
              <td>
                <span className={`status-tag status-tag--missao-${m.estado}`}>{ESTADO_LABEL[m.estado]}</span>
              </td>
              <td>{m.motivoPausa ?? "—"}</td>
              <td className="acoes-cell">
                {m.estado === "EmExecucao" && (
                  <>
                    <select
                      value={motivoPorMissao[m.id] ?? MOTIVOS_PAUSA[0]}
                      onChange={(e) => setMotivoPorMissao((prev) => ({ ...prev, [m.id]: e.target.value }))}
                      data-testid={`motivo-${m.id}`}
                    >
                      {MOTIVOS_PAUSA.map((motivo) => (
                        <option key={motivo} value={motivo}>
                          {motivo}
                        </option>
                      ))}
                    </select>
                    <button
                      className="button button--small"
                      disabled={aProcessar === m.id}
                      onClick={() => executar(() => missoesApi.pausar(m.id, motivoPorMissao[m.id] ?? MOTIVOS_PAUSA[0]), m.id)}
                      data-testid={`pausar-${m.id}`}
                    >
                      Pausar
                    </button>
                  </>
                )}
                {m.estado === "Pausada" && (
                  <>
                    <button
                      className="button button--small"
                      disabled={aProcessar === m.id}
                      onClick={() => executar(() => missoesApi.retomar(m.id), m.id)}
                      data-testid={`retomar-${m.id}`}
                    >
                      Retomar
                    </button>
                    <button
                      className="button button--small"
                      disabled={aProcessar === m.id}
                      onClick={() => executar(() => missoesApi.fechar(m.id), m.id)}
                      data-testid={`fechar-${m.id}`}
                    >
                      Fechar
                    </button>
                    <button
                      className="button button--small"
                      disabled={aProcessar === m.id}
                      onClick={() => executar(() => missoesApi.reatribuir(m.id, null), m.id)}
                      data-testid={`reatribuir-${m.id}`}
                    >
                      Reatribuir
                    </button>
                  </>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      {missoes.length === 0 && !erro && <p className="page__empty">Sem missões.</p>}
    </div>
  );
}
