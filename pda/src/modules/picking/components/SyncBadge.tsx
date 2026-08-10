import { useEffect, useState } from "react";
import { useLiveQuery } from "dexie-react-hooks";
import { db } from "../db";

export function SyncBadge() {
  const pendentes = useLiveQuery(() => db.outbox.count(), [], 0);
  const [online, setOnline] = useState(navigator.onLine);

  useEffect(() => {
    const atualizar = () => setOnline(navigator.onLine);
    window.addEventListener("online", atualizar);
    window.addEventListener("offline", atualizar);
    return () => {
      window.removeEventListener("online", atualizar);
      window.removeEventListener("offline", atualizar);
    };
  }, []);

  if (online && !pendentes) return null;

  return (
    <p className={`sync-badge${online ? "" : " sync-badge--offline"}`} data-testid="sync-badge">
      {online ? `A sincronizar… ${pendentes} pendente(s)` : `Offline · ${pendentes} por sincronizar`}
    </p>
  );
}
