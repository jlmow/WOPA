import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useSession } from "../SessionContext";
import { zonasApi, type Zona } from "../../shared/api/zonas";

export function ZonaPicker() {
  const [zonas, setZonas] = useState<Zona[]>([]);
  const [erro, setErro] = useState<string | null>(null);
  const { modulo, selecionarZona } = useSession();
  const navigate = useNavigate();

  useEffect(() => {
    zonasApi
      .list()
      .then(setZonas)
      .catch((err) => setErro((err as Error).message));
  }, []);

  function escolher(zona: Zona) {
    selecionarZona(zona);
    navigate(`/${modulo}`);
  }

  return (
    <main className="app">
      <header className="app__header">
        <button className="link-button" onClick={() => navigate("/modulos")} data-testid="voltar-modulos">
          &larr; Módulos
        </button>
        <h1>Em que zona estás?</h1>
      </header>

      {erro && <p className="scan-screen__message scan-screen__message--erro">{erro}</p>}

      <ul className="option-list" data-testid="zona-list">
        {zonas.map((zona) => (
          <li key={zona.id}>
            <button
              className="option-card"
              onClick={() => escolher(zona)}
              data-testid={`zona-${zona.id}`}
            >
              <span className="option-card__codigo">{zona.codigo}</span>
              <span className="option-card__nome">{zona.nome}</span>
            </button>
          </li>
        ))}
      </ul>
    </main>
  );
}
