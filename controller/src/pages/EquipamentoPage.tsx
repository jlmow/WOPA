import { useEffect, useState } from "react";
import { paletesApi, type Palete } from "../shared/api/paletes";
import { cestosApi, type CestoInstancia } from "../shared/api/cestos";

/**
 * Registo de paletes e cestos (ADR-035) — equipamento físico
 * reutilizável, com matrícula própria. Pré-carregado aqui: o pda
 * recusa qualquer matrícula desconhecida no gate de montagem e no
 * pick, em vez de a aceitar às cegas.
 */
export function EquipamentoPage() {
  const [paletes, setPaletes] = useState<Palete[]>([]);
  const [cestos, setCestos] = useState<CestoInstancia[]>([]);
  const [novaMatriculaPalete, setNovaMatriculaPalete] = useState("");
  const [novaMatriculaCesto, setNovaMatriculaCesto] = useState("");
  const [erroPalete, setErroPalete] = useState<string | null>(null);
  const [erroCesto, setErroCesto] = useState<string | null>(null);
  const [aCriarPalete, setACriarPalete] = useState(false);
  const [aCriarCesto, setACriarCesto] = useState(false);

  function carregarPaletes() {
    paletesApi.listar().then(setPaletes).catch((err) => setErroPalete((err as Error).message));
  }

  function carregarCestos() {
    cestosApi.listar().then(setCestos).catch((err) => setErroCesto((err as Error).message));
  }

  useEffect(() => {
    carregarPaletes();
    carregarCestos();
  }, []);

  async function criarPalete(e: React.FormEvent) {
    e.preventDefault();
    if (!novaMatriculaPalete.trim() || aCriarPalete) return;
    setACriarPalete(true);
    setErroPalete(null);
    try {
      await paletesApi.criar(novaMatriculaPalete.trim());
      setNovaMatriculaPalete("");
      carregarPaletes();
    } catch (err) {
      setErroPalete((err as Error).message);
    } finally {
      setACriarPalete(false);
    }
  }

  async function criarCesto(e: React.FormEvent) {
    e.preventDefault();
    if (!novaMatriculaCesto.trim() || aCriarCesto) return;
    setACriarCesto(true);
    setErroCesto(null);
    try {
      await cestosApi.criar(novaMatriculaCesto.trim());
      setNovaMatriculaCesto("");
      carregarCestos();
    } catch (err) {
      setErroCesto((err as Error).message);
    } finally {
      setACriarCesto(false);
    }
  }

  return (
    <div className="page">
      <header className="page__header">
        <h1>Equipamento</h1>
        <p className="page__subtitle">
          Paletes e cestos são reaproveitados — a matrícula regista-se aqui uma vez; o pda recusa qualquer matrícula
          desconhecida ao montar uma plataforma ou ao picar (ADR-035).
        </p>
      </header>

      <section className="panel">
        <h2>Paletes</h2>

        {erroPalete && <p className="page__error">{erroPalete}</p>}

        <form className="form-row" onSubmit={criarPalete}>
          <label>
            Matrícula
            <input
              value={novaMatriculaPalete}
              onChange={(e) => setNovaMatriculaPalete(e.target.value)}
              placeholder="Ler ou escrever a matrícula"
              data-testid="nova-matricula-palete"
            />
          </label>
          <button
            type="submit"
            className="button button--primary"
            disabled={!novaMatriculaPalete.trim() || aCriarPalete}
            data-testid="criar-palete"
          >
            Registar palete
          </button>
        </form>

        <table className="data-table" data-testid="paletes-table">
          <thead>
            <tr>
              <th>Matrícula</th>
              <th>Estado</th>
              <th>Localização atual</th>
            </tr>
          </thead>
          <tbody>
            {paletes.map((p) => (
              <tr key={p.id} data-testid={`palete-${p.id}`}>
                <td>{p.matricula}</td>
                <td>
                  <span className={`status-tag ${p.ativa ? "status-tag--Concluida" : "status-tag--erro"}`}>
                    {p.ativa ? "Ativa" : "Inativa"}
                  </span>
                </td>
                <td>{p.localizacaoCodigo ?? "Em circulação"}</td>
              </tr>
            ))}
          </tbody>
        </table>
        {paletes.length === 0 && !erroPalete && <p className="page__empty">Sem paletes registadas.</p>}
      </section>

      <section className="panel">
        <h2>Cestos</h2>

        {erroCesto && <p className="page__error">{erroCesto}</p>}

        <form className="form-row" onSubmit={criarCesto}>
          <label>
            Matrícula
            <input
              value={novaMatriculaCesto}
              onChange={(e) => setNovaMatriculaCesto(e.target.value)}
              placeholder="Ler ou escrever a matrícula"
              data-testid="nova-matricula-cesto"
            />
          </label>
          <button
            type="submit"
            className="button button--primary"
            disabled={!novaMatriculaCesto.trim() || aCriarCesto}
            data-testid="criar-cesto"
          >
            Registar cesto
          </button>
        </form>

        <table className="data-table" data-testid="cestos-table">
          <thead>
            <tr>
              <th>Matrícula</th>
              <th>Tipo</th>
              <th>Estado</th>
              <th>Localização atual</th>
            </tr>
          </thead>
          <tbody>
            {cestos.map((c) => (
              <tr key={c.id} data-testid={`cesto-${c.id}`}>
                <td>{c.matricula}</td>
                <td>{c.tipoCestoCodigo}</td>
                <td>
                  <span className={`status-tag ${c.estado === "Livre" ? "status-tag--Concluida" : "status-tag--EmProgresso"}`}>
                    {c.estado}
                  </span>
                </td>
                <td>{c.localizacaoCodigo ?? "Em circulação"}</td>
              </tr>
            ))}
          </tbody>
        </table>
        {cestos.length === 0 && !erroCesto && <p className="page__empty">Sem cestos registados.</p>}
      </section>
    </div>
  );
}
