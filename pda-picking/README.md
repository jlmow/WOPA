# WOPA pda-picking

Prova de conceito da app de picking para PDA Android, feita como **PWA
(TypeScript + React + Vite)** em vez de app nativa — ver `ARCHITECTURE.md`
na raiz do repositório para a justificação da escolha.

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
