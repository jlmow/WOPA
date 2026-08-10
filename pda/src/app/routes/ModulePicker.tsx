import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useSession } from "../SessionContext";
import { modulosApi, type Modulo } from "../../shared/api/modulos";

export function ModulePicker() {
  const [modulos, setModulos] = useState<Modulo[]>([]);
  const [erro, setErro] = useState<string | null>(null);
  const { operador, selecionarModulo, terminarSessao } = useSession();
  const navigate = useNavigate();

  useEffect(() => {
    modulosApi
      .list()
      .then(setModulos)
      .catch((err) => setErro((err as Error).message));
  }, []);

  function escolher(modulo: Modulo) {
    if (!modulo.disponivel) return;
    selecionarModulo(modulo.slug);
    navigate("/zona");
  }

  function sair() {
    terminarSessao();
    navigate("/login");
  }

  return (
    <main className="app">
      <header className="app__header app__header--session">
        <div>
          <p className="app__eyebrow">Operador {operador}</p>
          <h1>Módulos</h1>
        </div>
        <button className="link-button" onClick={sair} data-testid="terminar-sessao">
          Terminar sessão
        </button>
      </header>

      {erro && <p className="scan-screen__message scan-screen__message--erro">{erro}</p>}

      <ul className="option-list" data-testid="module-list">
        {modulos.map((modulo) => (
          <li key={modulo.slug}>
            <button
              className="option-card"
              disabled={!modulo.disponivel}
              onClick={() => escolher(modulo)}
              data-testid={`modulo-${modulo.slug}`}
            >
              <span className="option-card__nome">{modulo.nome}</span>
              {!modulo.disponivel && <span className="option-card__tag">Em breve</span>}
            </button>
          </li>
        ))}
      </ul>
    </main>
  );
}
