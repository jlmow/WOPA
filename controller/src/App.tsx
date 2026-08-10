import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import { AppShell } from "./layout/AppShell";
import { OrdensPreparacaoPage } from "./pages/OrdensPreparacaoPage";
import { MissoesPage } from "./pages/MissoesPage";

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route element={<AppShell />}>
          <Route path="/" element={<Navigate to="/ordens-preparacao" replace />} />
          <Route path="/ordens-preparacao" element={<OrdensPreparacaoPage />} />
          <Route path="/missoes" element={<MissoesPage />} />
        </Route>
      </Routes>
    </BrowserRouter>
  );
}
