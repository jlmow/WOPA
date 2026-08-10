# WOPA — Arquitetura

> Documento de trabalho com os requisitos de arquitetura recolhidos e as
> recomendações de stack em discussão. Vai sendo atualizado à medida que
> as decisões forem tomadas.

## Módulos e onde correm

### Desktop (Windows / Android) — com frontend
- **controller**
- **core-config**

### API "Cérebro" — sem frontend
- **orchestrator**
  - Integrador com a BD do software a desenvolver e com o ERP do cliente.

### Software tipo POS (picagem de códigos de barras pelos operadores)
- **packing**

### Software para PDAs Android
- **pda-abastecimento**
- **pda-picking**
- **pda-transporte**

## Base de dados
- **1 única base de dados Microsoft SQL Server** ("WOPA") para todas as
  funcionalidades dos vários módulos.

## Requisitos não-funcionais / regras
- Comunicação entre módulos via **APIs REST + JSON** (endpoints).
- Arquitetura assente em **servidores do cliente** (on-premise): dados
  sempre dentro das portas/rede do cliente, não em cloud pública.
- Hosting: **IIS** (aplicações/API) + **Microsoft SQL Server** (dados).
- **Regra de linguagem**: recente, sintaxe simples, alta performance.

## Recomendação de stack (proposta — a validar)

Dado que a infraestrutura já está definida como **IIS + SQL Server**
(ecossistema Microsoft), a opção com menos atrito e melhor integração
nativa é ficar dentro do ecossistema **.NET**, usando **C# / .NET 8
(LTS)** como linguagem única em toda a stack:

| Módulo | Proposta | Porquê |
|---|---|---|
| orchestrator ("Cérebro") | ASP.NET Core Web API (.NET 8), hospedado em IIS | Suporte nativo a IIS, endpoints REST/JSON, EF Core/Dapper para SQL Server, camada natural para integrar com o ERP |
| controller, core-config | .NET MAUI (ou Blazor Hybrid) | Mesmo código C# a correr em Windows e Android, sem duplicar equipa/linguagem |
| packing (POS) | Blazor Server ou WebAssembly, hospedado em IIS | Interface web leve, fácil de atualizar centralmente, compatível com leitores de código de barras (input tipo teclado) |
| pda-abastecimento / pda-picking / pda-transporte | .NET MAUI Android | Reutiliza a mesma linguagem/stack; se for preciso SDK nativo de leitor (Zebra/Honeywell), usam-se bindings Android dentro do MAUI |
| Base de dados | 1 SQL Server "WOPA", com **schemas separados por módulo** (`controller`, `orchestrator`, `packing`, `pda_abastecimento`, ...) | Cumpre o requisito de BD única mas mantém a organização/governança por módulo |

Princípio chave: os clientes (controller, core-config, packing, pda-*)
**não falam diretamente com a base de dados** — só através da API do
orchestrator. Isto centraliza a lógica de negócio e mantém uma única
fonte de verdade, alinhado com o requisito "APIs, endpoints, JSON".

### Vantagens desta proposta
- Uma única linguagem (C#) da API aos PDAs → equipa mais pequena e
  manutenção mais simples.
- Integração de primeira classe com IIS e SQL Server, sem camadas de
  tradução.
- .NET 8 é compilado, rápido, e tem sintaxe produtiva (cumpre a regra
  "recente, sintaxe fácil, performance").
- EF Core / Dapper são maduros e bem documentados para SQL Server.

### Riscos / tradeoffs a validar
- .NET MAUI ainda tem algumas arestas em Android, sobretudo se os PDAs
  forem equipamento industrial (Zebra, Honeywell) — convém validar
  cedo se o SDK do leitor tem bindings .NET decentes.
- Alternativas descartadas por desalinhamento com a infraestrutura:
  - Node.js/TypeScript + Electron/React Native: também moderno, mas
    obriga a gerir duas linguagens (JS front + backend) e não tem a
    mesma integração nativa com IIS.
  - Java/Kotlin + Spring Boot: robusto, mas corre naturalmente em
    Tomcat, não em IIS — mais fricção com a infraestrutura já definida.

## Próximos passos em aberto
- Validar SDK dos leitores de código de barras dos PDAs com MAUI.
- Definir se `packing` (POS) precisa de correr offline (ligação
  instável no armazém) — isso influencia Blazor Server vs WASM.
- Desenhar o esquema inicial da BD "WOPA" (schemas por módulo).
- Definir estratégia de autenticação entre módulos e a API orchestrator
  (ex.: JWT emitido pelo orchestrator).
