import type { ReactElement } from "react";
import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import { SessionProvider, useSession } from "./SessionContext";
import { Login } from "./routes/Login";
import { ModulePicker } from "./routes/ModulePicker";
import { ZonaPicker } from "./routes/ZonaPicker";
import { PickingModule } from "../modules/picking/PickingModule";

function RequireOperador({ children }: { children: ReactElement }) {
  const { operador } = useSession();
  return operador ? children : <Navigate to="/login" replace />;
}

function RequireZona({ children }: { children: ReactElement }) {
  const { operador, modulo, zona } = useSession();
  if (!operador) return <Navigate to="/login" replace />;
  if (!modulo) return <Navigate to="/modulos" replace />;
  if (!zona) return <Navigate to="/zona" replace />;
  return children;
}

function RaizInicial() {
  const { operador } = useSession();
  return <Navigate to={operador ? "/modulos" : "/login"} replace />;
}

export default function App() {
  return (
    <SessionProvider>
      <BrowserRouter>
        <Routes>
          <Route path="/login" element={<Login />} />
          <Route
            path="/modulos"
            element={
              <RequireOperador>
                <ModulePicker />
              </RequireOperador>
            }
          />
          <Route
            path="/zona"
            element={
              <RequireOperador>
                <ZonaPicker />
              </RequireOperador>
            }
          />
          <Route
            path="/picking"
            element={
              <RequireZona>
                <PickingModule />
              </RequireZona>
            }
          />
          <Route path="/" element={<RaizInicial />} />
          <Route path="*" element={<RaizInicial />} />
        </Routes>
      </BrowserRouter>
    </SessionProvider>
  );
}
