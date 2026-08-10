import { useEffect, useState } from "react";
import { pickingApi, type MissionSummary, type PickingTask } from "../shared/api/picking";

const ESTADO_LABEL: Record<PickingTask["estado"], string> = {
  Pendente: "Pendente",
  EmProgresso: "Em progresso",
  Concluida: "Concluída",
};

export function MissoesPage() {
  const [mission, setMission] = useState<MissionSummary | null>(null);
  const [tasks, setTasks] = useState<PickingTask[]>([]);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    Promise.all([pickingApi.getMission(), pickingApi.listTasks()])
      .then(([missao, lista]) => {
        setMission(missao);
        setTasks(lista);
      })
      .catch((err) => setErro((err as Error).message));
  }, []);

  return (
    <div className="page">
      <header className="page__header">
        <h1>Missão de picking</h1>
        {mission && (
          <p className="page__subtitle">
            {mission.codigo} · {mission.linhasConcluidas} de {mission.totalLinhas} linhas concluídas
          </p>
        )}
      </header>

      {erro && <p className="page__error">{erro}</p>}

      <table className="data-table" data-testid="missoes-table">
        <thead>
          <tr>
            <th>Localização</th>
            <th>SKU</th>
            <th>Descrição</th>
            <th>Plataforma</th>
            <th>Progresso</th>
            <th>Estado</th>
          </tr>
        </thead>
        <tbody>
          {tasks.map((task) => (
            <tr key={task.id} data-testid={`linha-${task.id}`}>
              <td>{task.localizacao}</td>
              <td>{task.sku}</td>
              <td>{task.descricao}</td>
              <td>{task.plataforma}</td>
              <td>
                {task.quantidadeLida}/{task.quantidadeAlvo}
              </td>
              <td>
                <span className={`status-tag status-tag--${task.estado}`}>{ESTADO_LABEL[task.estado]}</span>
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      {tasks.length === 0 && !erro && <p className="page__empty">Sem linhas de missão.</p>}
    </div>
  );
}
