import { Outlet } from "react-router-dom";
import { ConnectionStatus } from "../shared/components/ConnectionStatus";

// ADR-009: o estado de ligação ao servidor tem de aparecer em todos os
// ecrãs do pda, não só dentro do picking — por isso vive aqui, à volta de
// todas as rotas, e não dentro de um módulo específico.
export function RootLayout() {
  return (
    <div className="root-layout">
      <ConnectionStatus />
      <Outlet />
    </div>
  );
}
