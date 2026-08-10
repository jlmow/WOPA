import { NavLink, Outlet } from "react-router-dom";

const NAV_ITEMS = [
  { to: "/", label: "Missões", end: true },
  // Próximos ecrãs do controller (gestão de zonas, operadores, etc.) juntam-se aqui.
];

export function AppShell() {
  return (
    <div className="shell">
      <aside className="shell__sidebar">
        <p className="shell__brand">WOPA</p>
        <p className="shell__brand-sub">Controller</p>
        <nav className="shell__nav">
          {NAV_ITEMS.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.end}
              className={({ isActive }) => `shell__nav-link${isActive ? " shell__nav-link--active" : ""}`}
            >
              {item.label}
            </NavLink>
          ))}
        </nav>
      </aside>
      <main className="shell__content">
        <Outlet />
      </main>
    </div>
  );
}
