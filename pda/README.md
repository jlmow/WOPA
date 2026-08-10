# WOPA pda

App única de armazém para PDA Android, feita como **PWA (TypeScript +
React + Vite)** em vez de apps nativas separadas — ver `ARCHITECTURE.md`
na raiz do repositório para a justificação (ADR-002) e o modelo de
missão de picking (ADR-004).

Um só projeto, um só PWA instalado no dispositivo, com módulos
internos:

```
src/
  app/            → shell: login, seleção de módulo, seleção de zona, sessão
  modules/
    picking/      → em desenvolvimento
    transporte/    → por implementar ("em breve" no seletor de módulos)
    abastecimento/ → por implementar ("em breve" no seletor de módulos)
  shared/         → cliente API e tipos partilhados entre módulos
```

Fluxo do operador: **login (nº de operador) → módulos → zona → missão**.
No picking, ao atingir a quantidade de uma linha o sistema confirma e
avança sozinho para a linha seguinte — sem cliques extra — e mostra
sempre a plataforma/tote de destino de cada artigo.

O leitor de código de barras físico do PDA funciona em modo *keyboard
wedge*: escreve os dígitos no campo de input e envia Enter, tal como um
teclado. Não é necessário nenhum SDK nativo para o caso de uso base.

## Correr localmente

Pré-requisito: a API do `orchestrator` (`../orchestrator/src/Orchestrator.Api`)
a correr em `http://localhost:5080`.

```bash
npm install
npm run dev
```

Por omissão a app aponta para `http://localhost:5080`. Para apontar
para outro endereço, define `VITE_ORCHESTRATOR_URL` (ver `.env.example`).

## Build de produção

```bash
npm run build
```

Gera ficheiros estáticos em `dist/`, prontos a publicar no IIS (o mesmo
servidor que hospeda a API do orchestrator) — inclui manifest + service
worker, por isso é instalável como app no ecrã inicial do Android.

Nota: a app usa rotas do lado do cliente (React Router). Em produção
no IIS é preciso uma regra de rewrite para servir sempre `index.html`
em rotas desconhecidas (SPA fallback).
