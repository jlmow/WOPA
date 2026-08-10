import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { ordensSeparacaoApi, type OrdemSeparacao } from "../shared/api/ordensSeparacao";
import { ordensPreparacaoApi } from "../shared/api/ordensPreparacao";

export function PsPage() {
  const navigate = useNavigate();
  const [ps, setPs] = useState<OrdemSeparacao[]>([]);
  const [selecionados, setSelecionados] = useState<Set<string>>(new Set());
  const [erro, setErro] = useState<string | null>(null);
  const [aComporCliente, setAComporCliente] = useState("");
  const [aComporData, setAComporData] = useState("");
  const [aComporMorada, setAComporMorada] = useState("");
  const [aCompor, setACompor] = useState(false);

  function carregar() {
    ordensSeparacaoApi
      .listarAbertas()
      .then(setPs)
      .catch((err) => setErro((err as Error).message));
  }

  useEffect(carregar, []);

  function alternar(id: string) {
    setSelecionados((prev) => {
      const novo = new Set(prev);
      if (novo.has(id)) novo.delete(id);
      else novo.add(id);
      return novo;
    });
  }

  // Pré-preenche o formulário de composição a partir do primeiro PS
  // selecionado, sempre que a seleção deixa de estar vazia.
  useEffect(() => {
    if (selecionados.size === 0) return;
    const primeiro = ps.find((p) => selecionados.has(p.id));
    setAComporCliente((atual) => atual || primeiro?.cliente || "");
    setAComporData((atual) => atual || primeiro?.dataEntrega || "");
    setAComporMorada((atual) => atual || primeiro?.moradaEntrega || "");
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selecionados.size]);

  async function compor() {
    setACompor(true);
    setErro(null);
    try {
      const ordem = await ordensPreparacaoApi.compor({
        cliente: aComporCliente,
        dataEntrega: aComporData || null,
        moradaEntrega: aComporMorada || null,
        psIds: Array.from(selecionados),
      });
      navigate(`/ordens-preparacao?destaque=${ordem.id}`);
    } catch (err) {
      setErro((err as Error).message);
    } finally {
      setACompor(false);
    }
  }

  return (
    <div className="page">
      <header className="page__header">
        <h1>PS — Pedidos de separação</h1>
        <p className="page__subtitle">
          PS ainda por agrupar numa Ordem de Preparação (RF-CTL-01/02). Seleciona um ou mais para compor uma ordem.
        </p>
      </header>

      {erro && <p className="page__error">{erro}</p>}

      <table className="data-table" data-testid="ps-table">
        <thead>
          <tr>
            <th></th>
            <th>Documento</th>
            <th>Cliente</th>
            <th>Canal</th>
            <th>Refs</th>
            <th>Volume</th>
            <th>Peso</th>
            <th>Tipo indicativo</th>
          </tr>
        </thead>
        <tbody>
          {ps.map((p) => (
            <tr key={p.id} data-testid={`ps-${p.id}`}>
              <td>
                <input
                  type="checkbox"
                  checked={selecionados.has(p.id)}
                  onChange={() => alternar(p.id)}
                  data-testid={`ps-checkbox-${p.id}`}
                />
              </td>
              <td>{p.numeroDocumento}</td>
              <td>{p.cliente ?? "—"}</td>
              <td>{p.canal ?? "—"}</td>
              <td>{p.cubicagem?.nRefs ?? "—"}</td>
              <td>{p.cubicagem ? `${p.cubicagem.volumeLitros.toFixed(1)} L` : "—"}</td>
              <td>{p.cubicagem ? `${p.cubicagem.pesoKg.toFixed(1)} kg` : "—"}</td>
              <td>
                {p.cubicagem?.tipoIndicativo ?? "—"}
                {!!p.cubicagem?.nLinhasNaoCubicaveis && (
                  <span className="status-tag status-tag--erro" title="Linhas com ficha de artigo incompleta">
                    {" "}
                    {p.cubicagem.nLinhasNaoCubicaveis} c/ ficha incompleta
                  </span>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      {ps.length === 0 && !erro && <p className="page__empty">Sem PS por agrupar.</p>}

      {selecionados.size > 0 && (
        <div className="panel" data-testid="compor-panel">
          <h2>Compor Ordem de Preparação ({selecionados.size} PS selecionado{selecionados.size === 1 ? "" : "s"})</h2>
          <div className="form-row">
            <label>
              Cliente
              <input value={aComporCliente} onChange={(e) => setAComporCliente(e.target.value)} data-testid="compor-cliente" />
            </label>
            <label>
              Data de entrega
              <input type="date" value={aComporData} onChange={(e) => setAComporData(e.target.value)} data-testid="compor-data" />
            </label>
            <label>
              Morada de entrega
              <input value={aComporMorada} onChange={(e) => setAComporMorada(e.target.value)} data-testid="compor-morada" />
            </label>
          </div>
          <button className="button button--primary" onClick={compor} disabled={aCompor || !aComporCliente} data-testid="compor-submit">
            {aCompor ? "A compor…" : "Compor Ordem de Preparação"}
          </button>
        </div>
      )}
    </div>
  );
}
