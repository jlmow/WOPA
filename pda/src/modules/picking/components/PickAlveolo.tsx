import { useEffect, useRef, useState } from "react";
import type { AlveoloComStock, PickingTask } from "../types";
import { pickingApi } from "../api";

interface Props {
  task: PickingTask;
  onConfirmar: (alveoloId: string, quantidade: number) => void;
  onCancelar: () => void;
  onCompleted: (taskId: string) => void;
}

const ADVANCE_DELAY_MS = 600;

/**
 * Passo obrigatório depois do scan (ADR-022): o operador escolhe de que
 * alvéolo está a separar (lista de stock real, não um valor fixo) e
 * confirma a quantidade. O foco avança sozinho — escolher o alvéolo já
 * põe o cursor no campo de quantidade, pronto a aceitar a sugestão com
 * Enter ou a ser substituído por um número diferente.
 */
export function PickAlveolo({ task, onConfirmar, onCancelar, onCompleted }: Props) {
  const [opcoes, setOpcoes] = useState<AlveoloComStock[] | null>(null);
  const [erroCarregar, setErroCarregar] = useState<string | null>(null);
  const [selecionadoId, setSelecionadoId] = useState<string | null>(null);
  const [quantidade, setQuantidade] = useState<number>(0);
  const [erro, setErro] = useState<string | null>(null);
  const quantidadeRef = useRef<HTMLInputElement>(null);

  // Quando este pick completa a linha, o próprio orchestrator/estado local
  // já marca a tarefa como Concluída (ver PickingModule.handlePick) — só
  // falta mostrar a confirmação e avançar sozinho para a próxima.
  useEffect(() => {
    if (task.estado !== "Concluida") return;
    const temporizador = window.setTimeout(() => onCompleted(task.id), ADVANCE_DELAY_MS);
    return () => window.clearTimeout(temporizador);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [task.estado, task.id]);

  useEffect(() => {
    let cancelado = false;
    setOpcoes(null);
    setErroCarregar(null);
    pickingApi
      .alveolos(task.id)
      .then((lista) => {
        if (cancelado) return;
        setOpcoes(lista);
        if (lista.length > 0) {
          setSelecionadoId(lista[0].alveoloId);
          setQuantidade(lista[0].sugestaoQuantidade);
        }
      })
      .catch((err) => {
        if (cancelado) return;
        setErroCarregar(
          (err as Error).message || "Sem ligação — não é possível obter os alvéolos com stock agora.",
        );
      });
    return () => {
      cancelado = true;
    };
  }, [task.id]);

  // Escolher o alvéolo avança logo o foco para a quantidade (auto-avanço) —
  // e pré-seleciona o texto para um número novo substituir a sugestão com
  // um só toque, sem apagar primeiro.
  function selecionar(opcao: AlveoloComStock) {
    setSelecionadoId(opcao.alveoloId);
    setQuantidade(opcao.sugestaoQuantidade);
    setErro(null);
    requestAnimationFrame(() => {
      quantidadeRef.current?.focus();
      quantidadeRef.current?.select();
    });
  }

  const selecionado = opcoes?.find((o) => o.alveoloId === selecionadoId) ?? null;
  const maximo = selecionado ? Math.min(task.quantidadeAlvo - task.quantidadeLida, selecionado.quantidadeDisponivel) : 0;

  function handleConfirmar(e: React.FormEvent) {
    e.preventDefault();
    if (!selecionado) return;
    if (quantidade <= 0 || quantidade > maximo) {
      setErro(`Introduz uma quantidade entre 1 e ${maximo}.`);
      return;
    }
    onConfirmar(selecionado.alveoloId, quantidade);
  }

  return (
    <div className="scan-screen" data-testid="pick-alveolo">
      <button className="link-button" onClick={onCancelar} data-testid="cancelar-pick">
        &larr; Ler outro código
      </button>

      <h2>{task.descricao}</h2>
      <p className="scan-screen__meta">
        SKU {task.sku} · Faltam <strong>{task.quantidadeAlvo - task.quantidadeLida}</strong>
      </p>

      {task.estado === "Concluida" && (
        <p className="scan-screen__message scan-screen__message--info" data-testid="message">
          Linha concluída. A avançar…
        </p>
      )}

      {task.estado !== "Concluida" && erroCarregar && (
        <>
          <p className="scan-screen__message scan-screen__message--erro">{erroCarregar}</p>
          <button
            type="button"
            onClick={() => {
              setErroCarregar(null);
              setOpcoes(null);
            }}
            data-testid="tentar-novamente-alveolos"
          >
            Tentar novamente
          </button>
        </>
      )}

      {task.estado !== "Concluida" && opcoes === null && !erroCarregar && <p>A obter alvéolos com stock…</p>}

      {task.estado !== "Concluida" && opcoes !== null && opcoes.length === 0 && (
        <p className="scan-screen__message scan-screen__message--erro">
          Sem stock deste artigo em nenhum alvéolo desta zona.
        </p>
      )}

      {task.estado !== "Concluida" && opcoes !== null && opcoes.length > 0 && (
        <form onSubmit={handleConfirmar}>
          <p className="scan-screen__meta">Em que alvéolo estás?</p>
          <ul className="option-list" data-testid="alveolo-list">
            {opcoes.map((opcao) => (
              <li key={opcao.alveoloId}>
                <button
                  type="button"
                  className={`option-card${opcao.alveoloId === selecionadoId ? " option-card--selecionado" : ""}`}
                  onClick={() => selecionar(opcao)}
                  data-testid={`alveolo-${opcao.alveoloId}`}
                >
                  <span className="option-card__codigo">{opcao.codigo}</span>
                  <span className="option-card__nome">{opcao.quantidadeDisponivel} disponíveis</span>
                </button>
              </li>
            ))}
          </ul>

          <label htmlFor="pick-quantidade">Quantidade a separar</label>
          <input
            id="pick-quantidade"
            ref={quantidadeRef}
            data-testid="quantidade-input"
            type="number"
            min={1}
            max={maximo}
            value={quantidade}
            onChange={(e) => setQuantidade(Number(e.target.value))}
            autoComplete="off"
          />

          <button type="submit" disabled={!selecionado || quantidade <= 0} data-testid="confirmar-pick">
            Confirmar
          </button>

          {erro && (
            <p className="scan-screen__message scan-screen__message--erro" data-testid="pick-erro">
              {erro}
            </p>
          )}
        </form>
      )}
    </div>
  );
}
