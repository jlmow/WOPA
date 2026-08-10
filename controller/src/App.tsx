import { BrowserRouter, Route, Routes } from "react-router-dom";
import { AppShell } from "./layout/AppShell";
import { MissoesPage } from "./pages/MissoesPage";

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route element={<AppShell />}>
          <Route path="/" element={<MissoesPage />} />
        </Route>
      </Routes>
    </BrowserRouter>
  );
}
