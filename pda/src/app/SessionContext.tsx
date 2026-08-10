import { createContext, useContext, useState, type ReactNode } from "react";
import type { Zona } from "../shared/api/zonas";

const STORAGE_KEY = "wopa-pda-sessao";

interface StoredSession {
  operador: string | null;
  modulo: string | null;
  zona: Zona | null;
}

const EMPTY_SESSION: StoredSession = { operador: null, modulo: null, zona: null };

function loadStored(): StoredSession {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? { ...EMPTY_SESSION, ...(JSON.parse(raw) as StoredSession) } : EMPTY_SESSION;
  } catch {
    return EMPTY_SESSION;
  }
}

interface SessionContextValue extends StoredSession {
  login: (operador: string) => void;
  selecionarModulo: (modulo: string) => void;
  selecionarZona: (zona: Zona) => void;
  terminarSessao: () => void;
}

const SessionContext = createContext<SessionContextValue | null>(null);

export function SessionProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<StoredSession>(loadStored);

  function update(patch: Partial<StoredSession>) {
    setSession((prev) => {
      const next = { ...prev, ...patch };
      localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
      return next;
    });
  }

  const value: SessionContextValue = {
    ...session,
    login: (operador) => update({ operador, modulo: null, zona: null }),
    // Trocar de módulo obriga a escolher zona de novo — zonas são específicas do módulo.
    selecionarModulo: (modulo) => update({ modulo, zona: null }),
    selecionarZona: (zona) => update({ zona }),
    terminarSessao: () => {
      localStorage.removeItem(STORAGE_KEY);
      setSession(EMPTY_SESSION);
    },
  };

  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}

export function useSession(): SessionContextValue {
  const ctx = useContext(SessionContext);
  if (!ctx) throw new Error("useSession tem de ser usado dentro de <SessionProvider>");
  return ctx;
}
