# WOPA — Documento de Arquitetura

| | |
|---|---|
| **Estado** | Em desenvolvimento — validado com PoC funcional |
| **Última atualização** | Picking PoC (orchestrator + pda-picking) |
| **Âmbito** | Todos os módulos do projeto WOPA (Warehouse Order & Picking Automation) |

Este documento é a referência viva da arquitetura do WOPA. Regista as
decisões tomadas (e porquê), a stack por módulo, os princípios de UX
que qualquer ecrã de PDA tem de respeitar, e o que já foi validado em
PoC vs. o que ainda está por construir.

---

## 1. Visão geral

O WOPA é composto por um conjunto de aplicações que partilham uma
única base de dados e comunicam exclusivamente por API. Não há acesso
direto a base de dados fora do `orchestrator` — todos os clientes
(desktop, POS, PDAs) são "burros" em relação a dados: pedem, mostram,
enviam. A lógica de negócio e a integração com o ERP vivem no
`orchestrator`.

```mermaid
flowchart LR
    subgraph Clientes
        controller["controller\n(Windows, PWA/desktop)"]
        coreconfig["core-config\n(Windows, PWA/desktop)"]
        packing["packing\n(POS, Blazor)"]
        pdapick["pda-picking\n(Android, PWA)"]
        pdaaba["pda-abastecimento\n(Android, PWA)"]
        pdatrans["pda-transporte\n(Android, PWA)"]
    end

    subgraph Servidor["Servidor do cliente (on-premise, IIS)"]
        orchestrator["orchestrator\nASP.NET Core Web API\n(\"Cérebro\")"]
        db[("SQL Server\nWOPA")]
    end

    erp["ERP do cliente"]

    controller -- REST/JSON --> orchestrator
    coreconfig -- REST/JSON --> orchestrator
    packing -- REST/JSON --> orchestrator
    pdapick -- REST/JSON --> orchestrator
    pdaaba -- REST/JSON --> orchestrator
    pdatrans -- REST/JSON --> orchestrator

    orchestrator --> db
    orchestrator <-- integração --> erp
```

**Princípio inegociável:** nenhum cliente fala diretamente com a base
de dados ou com o ERP. Tudo passa pelo `orchestrator`.

---

## 2. Módulos

| Módulo | Tipo de posto de trabalho | Responsabilidade |
|---|---|---|
| `orchestrator` | Servidor (sem UI) | "Cérebro": API REST/JSON central, regras de negócio, integração com a BD WOPA e com o ERP do cliente |
| `controller` | Desktop (Windows) | Consola de controlo/gestão operacional |
| `core-config` | Desktop (Windows) | Configuração do sistema (parametrização) |
| `packing` | Posto fixo tipo POS | Picagem/embalamento de encomendas por operadores num posto fixo |
| `pda-picking` | PDA Android (mobilidade) | Picking de artigos no armazém |
| `pda-abastecimento` | PDA Android (mobilidade) | Reabastecimento de localizações de picking |
| `pda-transporte` | PDA Android (mobilidade) | Movimentação/transporte de paletes e cargas |

---

## 3. Stack tecnológica

### 3.1 Regra geral

A infraestrutura do cliente está fixada em **IIS + Microsoft SQL
Server** (on-premise, dados dentro da rede do cliente). Dado isso, o
`orchestrator` fica em **.NET 8 (C#)**, por ser a opção com menor
atrito de integração nesse ecossistema, cumprindo o requisito de
"linguagem recente, sintaxe simples e de alta performance".

### 3.2 Por módulo

| Módulo | Tecnologia | Porquê |
|---|---|---|
| `orchestrator` | ASP.NET Core Web API (.NET 8), hospedado em IIS | Suporte nativo a IIS; EF Core/Dapper para SQL Server; endpoints REST/JSON; ponto único de integração com o ERP |
| `controller`, `core-config` | A definir — candidato: .NET MAUI ou Blazor Hybrid (Windows) | Apps de secretária Windows; não têm o requisito de mobilidade dos PDAs |
| `packing` | Blazor (Server ou WASM), hospedado em IIS | Posto fixo tipo POS; interface web leve, atualização central, compatível com leitor de código de barras em modo teclado |
| `pda-picking`, `pda-abastecimento`, `pda-transporte` | **PWA — TypeScript + React + Vite** (ver ADR-002) | Instalável no Android, sem SDK nativo, testável de ponta a ponta, atualização centralizada |
| Base de dados | 1 SQL Server ("WOPA"), com **schema por módulo** (`orchestrator`, `packing`, `pda_picking`, ...) | Cumpre "1 base de dados" mantendo governança e fronteiras claras entre módulos |

### 3.3 Regra fixa: todo o software Android é PWA

**Qualquer módulo WOPA que corra num PDA/dispositivo Android usa
sempre TypeScript + React + Vite, empacotado como PWA instalável.**
Não é uma escolha caso a caso — é a stack por omissão para mobilidade
Android neste projeto (ver ADR-002 para a justificação completa).

Isto aplica-se hoje a `pda-picking`, `pda-abastecimento` e
`pda-transporte`, e a qualquer módulo Android futuro.

---

## 4. Princípios de UX para PDA — picking orientado a performance

Os ecrãs de PDA (picking, abastecimento, transporte) são usados por
operadores em movimento, muitas vezes de luvas, durante um turno
inteiro. **Velocidade e número de toques importam tanto como
correção.** Estas regras aplicam-se a qualquer ecrã de PDA construído
no WOPA:

1. **O leitor é o input principal, não o dedo.** O campo de leitura
   está sempre focado; ler um código de barras nunca deve exigir tocar
   no ecrã primeiro.
2. **Ler substitui clicar.** Sempre que uma leitura resolve
   inequivocamente uma ação (ex.: quantidade atingida → tarefa
   concluída), o sistema avança sozinho — não pede confirmação por
   toque para algo que a própria leitura já confirmou.
3. **Avanço automático entre tarefas.** Ao concluir uma tarefa, o
   sistema avança automaticamente para a próxima da rota (por
   localização), sem o operador ter de voltar à lista e escolher.
4. **Erros não bloqueiam.** Uma leitura errada mostra feedback
   imediato (mensagem + eventualmente som/vibração) mas não abre
   diálogos nem exige um toque para "fechar" — o campo continua pronto
   para nova leitura.
5. **Sem opções desnecessárias no ecrã de picking.** O ecrã mostra
   apenas o essencial para a ação corrente (localização, artigo,
   progresso). Configurações, filtros e ações raras vivem fora do
   fluxo de picking.
6. **Leituras repetidas ou a mais não partem o fluxo.** O sistema
   tolera o operador ler o mesmo código mais vezes que o necessário
   sem gerar erro nem duplicar a contagem além do alvo.
7. **Cada toque extra tem de se justificar.** Antes de adicionar um
   botão, um passo de confirmação ou um ecrã intermédio a um fluxo de
   PDA, a pergunta é: "isto pode ser resolvido por uma leitura, ou
   evitado por completo?"

Estes princípios foram validados na PoC do `pda-picking` (ver secção
6): ler o código certo é a única ação do operador — sem confirmar,
sem escolher a próxima tarefa manualmente.

---

## 5. Comunicação entre módulos

- Toda a comunicação é **REST sobre HTTP(S), payloads em JSON**.
- Os clientes (PDAs, desktop, packing) só chamam o `orchestrator` —
  nunca a base de dados nem o ERP diretamente.
- Em produção, `orchestrator` e os frontends web (PWAs, Blazor) ficam
  atrás do mesmo IIS/domínio, eliminando a necessidade de CORS.
- Autenticação entre módulos e o `orchestrator`: **por decidir** (ver
  secção 8).

---

## 6. Estado atual — o que já foi validado

| Módulo | Estado | Nota |
|---|---|---|
| `orchestrator` — endpoints de picking | ✅ PoC funcional | ASP.NET Core Web API real, testada (listar/ler/confirmar tarefas) |
| `pda-picking` | ✅ PoC funcional | PWA React/TS/Vite, fluxo de picking sem cliques de confirmação, testado de ponta a ponta com um browser real |
| `pda-abastecimento`, `pda-transporte` | ⏳ Por começar | Seguem a mesma stack (PWA) e os mesmos princípios de UX do `pda-picking` |
| `controller`, `core-config` | ⏳ Por começar | Stack de desktop ainda por confirmar |
| `packing` | ⏳ Por começar | |
| Base de dados WOPA (SQL Server) | ⏳ Por desenhar | A PoC usa dados em memória no `orchestrator` como substituto temporário |

---

## 7. Decisões de arquitetura (ADR)

### ADR-001 — Backend em .NET 8 / ASP.NET Core

- **Contexto:** infraestrutura do cliente fixada em IIS + SQL Server.
- **Decisão:** o `orchestrator` é uma Web API ASP.NET Core (.NET 8).
- **Porquê:** integração nativa com IIS e SQL Server, sem camadas de
  tradução; linguagem moderna, compilada e produtiva.
- **Alternativas consideradas:** Node.js/TypeScript (perde a
  integração nativa com IIS), Java/Kotlin + Spring Boot (corre
  naturalmente em Tomcat, não em IIS).

### ADR-002 — PWA (TypeScript + React + Vite) para todo o software Android

- **Contexto:** os PDAs de armazém precisam de uma app instalável,
  rápida a desenvolver e fácil de manter, correndo sobre Android.
  MAUI/Android nativo exigem SDK Android + emulador/dispositivo real
  para compilar e testar — infraestrutura pesada e difícil de validar
  de ponta a ponta em qualquer ambiente de desenvolvimento.
- **Decisão:** todo o software WOPA para Android/PDA é construído como
  **PWA em TypeScript + React + Vite**, instalável no ecrã principal
  do dispositivo.
- **Porquê:**
  - Os leitores de código de barras de PDAs industriais (Zebra,
    Honeywell, etc.) tipicamente funcionam em modo *keyboard wedge* —
    injetam o código lido como se fosse escrito num campo de texto.
    Isto funciona out-of-the-box numa PWA, sem SDK nativo.
  - Distribuição e atualização centralizadas: publica-se no IIS, os
    dispositivos atualizam sozinhos (service worker), sem processo de
    instalação de APKs por dispositivo.
  - Uma PWA hospeda-se como ficheiros estáticos no mesmo IIS da API —
    coerente com a regra de infraestrutura on-premise do projeto.
  - Stack testável de ponta a ponta em qualquer máquina de
    desenvolvimento (browser + testes automatizados), sem depender de
    Android SDK/emulador.
- **Consequência:** esta é a stack por omissão para qualquer módulo
  Android futuro do WOPA — não é reavaliada projeto a projeto.
- **Riscos aceites:** funcionalidades muito específicas de hardware
  (ex.: SDK proprietário de um leitor que não exponha modo teclado)
  podem exigir investigação adicional; até à data não há indicação de
  que isso seja necessário.

### ADR-003 — Uma base de dados, schemas por módulo

- **Contexto:** requisito do cliente de uma única base de dados SQL
  Server ("WOPA") para todas as funcionalidades.
- **Decisão:** uma instância de SQL Server, com um schema dedicado por
  módulo (`orchestrator`, `packing`, `pda_picking`, ...).
- **Porquê:** cumpre o requisito de BD única, mantendo fronteiras
  claras de propriedade dos dados entre módulos.

---

## 8. Em aberto

- Autenticação/autorização entre clientes e o `orchestrator` (ex.: JWT
  emitido pelo `orchestrator`, um por dispositivo/utilizador).
- Stack definitiva para `controller` e `core-config` (desktop
  Windows).
- Se `packing` precisa de funcionar offline (ligação instável no
  armazém) — decide entre Blazor Server e WASM.
- Desenho do esquema inicial da base de dados WOPA (schemas por
  módulo, tabelas de picking/abastecimento/transporte).
- Estratégia de sincronização/offline para os PDAs quando a rede
  Wi-Fi do armazém falha (fila local + reenvio, ou bloquear leitura
  até haver ligação?).
