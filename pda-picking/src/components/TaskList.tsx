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

export function TaskList({ tasks, onSelect }: Props) {
  return (
    <ul className="task-list" data-testid="task-list">
      {tasks.map((task) => (
        <li key={task.id}>
          <button
            className={`task-card task-card--${task.estado}`}
            onClick={() => onSelect(task)}
            data-testid={`task-${task.id}`}
          >
            <span className="task-card__loc">{task.localizacao}</span>
            <span className="task-card__desc">{task.descricao}</span>
            <span className="task-card__sku">{task.sku}</span>
            <span className="task-card__qty">
              {task.quantidadeLida}/{task.quantidadeAlvo}
            </span>
            <span className="task-card__status">{statusLabel[task.estado]}</span>
          </button>
        </li>
      ))}
    </ul>
  );
}
