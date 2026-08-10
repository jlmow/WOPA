import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useSession } from "../SessionContext";

const TECLAS = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"];

export function Login() {
  const [operador, setOperador] = useState("");
  const { login } = useSession();
  const navigate = useNavigate();

  function premir(tecla: string) {
    if (tecla === "") return;
    if (tecla === "⌫") {
      setOperador((prev) => prev.slice(0, -1));
      return;
    }
    if (operador.length >= 6) return;
    setOperador((prev) => prev + tecla);
  }

  function entrar() {
    if (!operador) return;
    login(operador);
    navigate("/modulos");
  }

  return (
    <main className="app app--centered">
      <div className="login">
        <p className="login__eyebrow">WOPA</p>
        <h1>Número de operador</h1>
        <div className="login__display" data-testid="operador-display">
          {operador || "· · · ·"}
        </div>

        <div className="keypad" data-testid="keypad">
          {TECLAS.map((tecla, i) =>
            tecla === "" ? (
              <span key={i} />
            ) : (
              <button
                key={i}
                type="button"
                className="keypad__key"
                onClick={() => premir(tecla)}
                data-testid={`tecla-${tecla === "⌫" ? "apagar" : tecla}`}
              >
                {tecla}
              </button>
            ),
          )}
        </div>

        <button
          className="login__entrar"
          onClick={entrar}
          disabled={!operador}
          data-testid="entrar-button"
        >
          Entrar
        </button>
      </div>
    </main>
  );
}
