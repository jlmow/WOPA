# WOPA controller

Consola de controlo/gestão operacional, na mesma stack do `pda`
(TypeScript + React + Vite) mas com layout desktop — ver
`ARCHITECTURE.md` na raiz do repositório (ADR-006) para a
justificação de unificar a stack de frontend, e a secção 3.6 para como
se resolve hardware (leitores/impressoras) sem sair desta stack.

Estado atual: scaffold + um primeiro ecrã real, "Missões" — mostra as
linhas da missão de picking corrente (dados reais do `orchestrator`,
os mesmos que o `pda` consome), em tabela. É o ponto de partida para
onde o `controller` virá a gerar as ondas/missões que o `pda`
consome — ainda por desenhar.

## Correr localmente

Pré-requisito: a API do `orchestrator` (`../orchestrator/src/Orchestrator.Api`)
a correr em `http://localhost:5080`.

```bash
npm install
npm run dev -- --port 5174
```

(O `pda` já usa a porta 5173 por omissão; o `orchestrator` tem CORS
liberado para 5173 e 5174 em desenvolvimento.)

## Build de produção

```bash
npm run build
```

Gera ficheiros estáticos em `dist/`, prontos a publicar no IIS.
