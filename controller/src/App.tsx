import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import { AppShell } from "./layout/AppShell";
import { PsPage } from "./pages/PsPage";
import { OrdensPreparacaoPage } from "./pages/OrdensPreparacaoPage";
import { MissoesPage } from "./pages/MissoesPage";

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route element={<AppShell />}>
          <Route path="/" element={<Navigate to="/ps" replace />} />
          <Route path="/ps" element={<PsPage />} />
          <Route path="/ordens-preparacao" element={<OrdensPreparacaoPage />} />
          <Route path="/missoes" element={<MissoesPage />} />
        </Route>
      </Routes>
    </BrowserRouter>
  );
}
