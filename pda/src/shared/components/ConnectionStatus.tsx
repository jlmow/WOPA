import { useServerConnection } from "../useServerConnection";

export function ConnectionStatus() {
  const ligado = useServerConnection();

  return (
    <div
      className={`connection-status${ligado ? "" : " connection-status--offline"}`}
      data-testid="connection-status"
      data-ligado={ligado}
    >
      <span className="connection-status__dot" />
      {ligado ? "Ligado ao servidor" : "Sem ligação ao servidor"}
    </div>
  );
}
