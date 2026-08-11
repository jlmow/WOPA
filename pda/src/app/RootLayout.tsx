import { Outlet } from "react-router-dom";
import { ConnectionStatus } from "../shared/components/ConnectionStatus";
import { InstallAndroidLink } from "../shared/components/InstallAndroidLink";

// ADR-009/ADR-023: o estado de ligação ao servidor e a ligação para
// instalar em Android têm de aparecer em todos os ecrãs do pda, não só
// dentro de um módulo específico — por isso vivem aqui, à volta de todas
// as rotas.
export function RootLayout() {
  return (
    <div className="root-layout">
      <div className="root-layout__bar">
        <ConnectionStatus />
        <InstallAndroidLink />
      </div>
      <Outlet />
    </div>
  );
}
