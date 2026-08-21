import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import { AppShell } from "./layout/AppShell";
import { OrdensPreparacaoPage } from "./pages/OrdensPreparacaoPage";
import { MissoesPage } from "./pages/MissoesPage";
import { CapacidadePage } from "./pages/CapacidadePage";
import { EquipamentoPage } from "./pages/EquipamentoPage";

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route element={<AppShell />}>
          <Route path="/" element={<Navigate to="/ordens-preparacao" replace />} />
          <Route path="/ordens-preparacao" element={<OrdensPreparacaoPage />} />
          <Route path="/missoes" element={<MissoesPage />} />
          <Route path="/capacidade" element={<CapacidadePage />} />
          <Route path="/equipamento" element={<EquipamentoPage />} />
        </Route>
      </Routes>
    </BrowserRouter>
  );
}
