import { useState } from "react";
import type { PickingTask } from "../types";

const statusLabel: Record<PickingTask["estado"], string> = {
  Pendente: "Pendente",
  EmProgresso: "Em progresso",
  Concluida: "Concluída",
};

interface Props {
  tasks: PickingTask[];
  onSelect: (task: PickingTask) => void;
}

type Filtro = "todos" | "porFazer";

export function TaskList({ tasks, onSelect }: Props) {
  const [filtro, setFiltro] = useState<Filtro>("todos");
  const porFazer = tasks.filter((t) => t.estado !== "Concluida");
  const visiveis = filtro === "todos" ? tasks : porFazer;

  return (
    <>
      <div className="segmented" data-testid="task-list-filtro">
        <button
          type="button"
          className={`segmented__option${filtro === "todos" ? " segmented__option--ativo" : ""}`}
          onClick={() => setFiltro("todos")}
        >
          Tudo <span className="segmented__count">{tasks.length}</span>
        </button>
        <button
          type="button"
          className={`segmented__option${filtro === "porFazer" ? " segmented__option--ativo" : ""}`}
          onClick={() => setFiltro("porFazer")}
        >
          Por fazer <span className="segmented__count">{porFazer.length}</span>
        </button>
      </div>

      <ul className="task-list" data-testid="task-list">
        {visiveis.map((task) => (
        <li key={task.id}>
          <button
            className={`task-card task-card--${task.estado}`}
            onClick={() => onSelect(task)}
            data-testid={`task-${task.id}`}
          >
            <span className="task-card__loc">{task.localizacao}</span>
            <span className="task-card__desc">{task.descricao}</span>
            <span className="task-card__sku">
              {task.codigoBarras} · Plataforma {task.plataforma}
            </span>
            <span className="task-card__qty">
              {task.quantidadeLida}/{task.quantidadeAlvo}
            </span>
            <span className="task-card__status">{statusLabel[task.estado]}</span>
          </button>
        </li>
        ))}
      </ul>
    </>
  );
}
