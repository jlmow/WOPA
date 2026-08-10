# WOPA — Documento de Arquitetura

| | |
|---|---|
| **Estado** | Em desenvolvimento — validado com PoC funcional |
| **Última atualização** | App `pda` (login → módulos → zona → missão de picking, com plataformas de destino) |
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
        controller["controller\n(Windows, layout desktop)"]
        coreconfig["core-config\n(Windows, layout desktop)"]
        packing["packing\n(POS, Blazor)"]
        pda["pda\n(Android, PWA — login → módulos → zona)\npicking · transporte · abastecimento"]
    end

    subgraph Servidor["Servidor do cliente (on-premise, IIS)"]
        orchestrator["orchestrator\nASP.NET Core Web API\n(\"Cérebro\")"]
        db[("SQL Server\nWOPA")]
    end

    erp["ERP do cliente"]

    controller -- REST/JSON --> orchestrator
    coreconfig -- REST/JSON --> orchestrator
    packing -- REST/JSON --> orchestrator
    pda -- REST/JSON --> orchestrator

    orchestrator --> db
    orchestrator <-- integração --> erp
```

**Princípio inegociável:** nenhum cliente fala diretamente com a base
de dados ou com o ERP. Tudo passa pelo `orchestrator`.

---

## 2. Módulos

| Módulo | Tipo de posto de trabalho | Responsabilidade |
|---|---|---|
| `orchestrator` | Servidor (sem UI) | "Cérebro": API REST/JSON central, regras de negócio, integração com a BD WOPA e com o ERP do cliente. É também quem monta as **missões** de picking (ver secção 4.1) que o `controller` vai gerar |
| `controller` | Desktop (Windows) | Consola de controlo/gestão operacional; gera as ondas/missões que o `pda` consome |
| `core-config` | Desktop (Windows) | Configuração do sistema (parametrização) |
| `packing` | Posto fixo tipo POS | Picagem/embalamento de encomendas por operadores num posto fixo |
| `pda` | PDA Android (mobilidade) | App única com os módulos `picking` (implementado), `transporte` e `abastecimento` (por implementar) — ver secção 4.1 |

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
| `controller`, `core-config` | **TypeScript + React + Vite**, layout desktop (ver ADR-006) | Uma só stack de frontend em todo o WOPA; hardware (leitores/impressoras) resolvido sem sair da stack web — ver secção 3.6 |
| `packing` | Blazor (Server ou WASM), hospedado em IIS | Posto fixo tipo POS; interface web leve, atualização central, compatível com leitor de código de barras em modo teclado |
| `pda` (módulos `picking`, `transporte`, `abastecimento`) | **PWA — TypeScript + React + Vite** (ver ADR-002) | Instalável no Android, sem SDK nativo, testável de ponta a ponta, atualização centralizada |
| Base de dados | 1 SQL Server ("WOPA"), com **schema por módulo** (`orchestrator`, `packing`, `pda_picking`, ...) | Cumpre "1 base de dados" mantendo governança e fronteiras claras entre módulos |

### 3.3 Regra fixa: todo o software Android é PWA

**Qualquer módulo WOPA que corra num PDA/dispositivo Android usa
sempre TypeScript + React + Vite, empacotado como PWA instalável.**
Não é uma escolha caso a caso — é a stack por omissão para mobilidade
Android neste projeto (ver ADR-002 para a justificação completa).

Isto aplica-se hoje ao projeto `pda` (módulos `picking`, `transporte` e
`abastecimento`), e a qualquer módulo Android futuro.

### 3.4 Um único projeto `pda`, não um projeto por módulo

`picking`, `transporte` e `abastecimento` vivem **dentro do mesmo
projeto `pda`** (`pda/src/modules/...`), não como três apps/repos
separados chamados a partir de um "WOPA-PDA" externo (ver ADR-005). Na
prática, o operador só instala uma app no dispositivo; login, sessão,
seleção de zona e o cliente da API são código partilhado entre os três
módulos.

### 3.5 Stack única de frontend, incluindo desktop (ADR-006)

`controller` e `core-config` correm em Windows, não em PDAs — a regra
da secção 3.3 não os obriga tecnicamente. Ainda assim, usam a **mesma
stack TypeScript + React + Vite** do `pda`, apenas com um layout
desktop (grelhas mais largas, tabelas, navegação lateral) em vez do
layout mobile-first dos PDAs. Isto dá **uma única stack de frontend em
todo o WOPA** — ver ADR-006. Continuam apps web separadas por projeto
(não módulos dentro do `pda`, porque o público e o propósito são
diferentes) — só a tecnologia é partilhada.

### 3.6 Hardware: leitores de código de barras e impressoras

O `controller` (e postos fixos como `packing`) lidam com hardware que
uma app web não controla da mesma forma que uma app nativa. Isto **não
é motivo para sair da stack web** — cada tipo de hardware tem um
caminho definido:

| Hardware | Como liga | Como se resolve |
|---|---|---|
| Leitor de código de barras (PDA, integrado) | Modo teclado (*keyboard wedge*) | Funciona nativamente em qualquer input HTML — sem API especial (já validado no `pda`) |
| Leitor de código de barras USB (Windows) | Normalmente também modo teclado (*keyboard wedge*) | Igual ao de cima — funciona out-of-the-box num campo de input focado |
| Impressora de etiquetas ZPL (Zebra, etc.) — **ligada em rede** | TCP/IP, porta 9100 (raw socket) | O `orchestrator` envia o ZPL diretamente para IP:porta da impressora — trabalho do backend, o browser nunca precisa de tocar na impressora |
| Impressora de talões / etiquetas — **ligada por USB/série a um PC** | USB ou porta série | **WebUSB / WebSerial** (suportado em Chrome/Edge, que já são os browsers-alvo no Windows): a página pede autorização ao dispositivo uma vez e depois envia os bytes em bruto (ESC/POS ou ZPL), sem diálogo de impressão do Windows |

**Princípio:** impressora em rede → o backend imprime; impressora
local por USB/série → o browser imprime via WebUSB/WebSerial. Em
nenhum dos casos é preciso sair da stack TypeScript/React nem instalar
software nativo adicional no posto de trabalho. Fica como item a
detalhar (endpoint de impressão no `orchestrator`, biblioteca de
geração de ZPL/ESC-POS) quando `controller`/`packing` chegarem a essa
funcionalidade — ver secção 8.

---

## 4. Modelo de missão e fluxo do PDA

### 4.1 Fluxo do operador: login → módulos → zona → missão

Inspirado em sistemas de picking de armazéns de grande escala (ex.:
IKEA, Amazon, DHL): o operador nunca escolhe o que fazer a seguir — o
sistema decide, o operador só executa.

1. **Login** — número de operador (curto, sem password no PDA;
   validação real fica para quando existir autenticação no
   `orchestrator`, ver secção 8).
2. **Módulos** — lista dos módulos disponíveis no `pda` (`picking`,
   `transporte`, `abastecimento`); os que ainda não estão implementados
   aparecem visíveis mas desativados ("em breve"), não escondidos.
3. **Zona** — em que zona do armazém o operador está agora
   (`GET /api/zonas`).
4. **Missão** — o módulo abre já na primeira linha por fazer; não há
   ecrã de "escolher tarefa" no caminho normal.

### 4.2 Missão de picking: plataforma de destino por linha

Uma missão de picking agrupa várias linhas (artigos a picar), tipicamente
provenientes de várias encomendas em simultâneo (picking em lote). Por
isso cada linha indica não só *o que* picar, mas **para que
plataforma/tote colocar** — sem essa indicação, misturar artigos de
encomendas diferentes no mesmo carrinho é o erro mais comum deste tipo
de sistema. Ao ler o código de barras certo, a linha conclui-se e
confirma-se sozinha, e a missão avança para a linha seguinte da rota
(ordenada por localização). Quando todas as linhas terminam, a missão
fecha e o ecrã assinala explicitamente a transição: **"Missão concluída
→ segue para o packing."**

Hoje as missões são geradas com dados fixos no `orchestrator` (PoC);
no desenho final, o `controller` é quem cria as ondas/missões, e o
`orchestrator` distribui-as aos PDAs.

### 4.3 Princípios de UX para PDA — picking orientado a performance

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

Estes princípios foram validados na PoC do módulo `picking` do `pda`
(ver secção 6): ler o código certo é a única ação do operador — sem
confirmar, sem escolher a próxima linha manualmente.

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
| `orchestrator` — endpoints de picking, zonas, módulos | ✅ PoC funcional | ASP.NET Core Web API real, testada (missão, leitura, confirmação, plataforma, zonas, módulos) |
| `pda` — shell (login, módulos, zona) | ✅ PoC funcional | React Router com sessão local; módulos indisponíveis aparecem desativados |
| `pda` — módulo `picking` | ✅ PoC funcional | Fluxo guiado (auto-início, avanço automático, plataforma de destino, progresso da missão), testado de ponta a ponta com um browser real |
| `pda` — módulos `transporte`, `abastecimento` | ⏳ Por começar | Já aparecem no seletor de módulos como "em breve"; seguem a mesma stack e os mesmos princípios de UX do `picking` |
| `controller` | 🚧 Em construção | Scaffold TypeScript/React/Vite, layout desktop (ver ADR-006) |
| `core-config` | ⏳ Por começar | Segue a mesma stack do `controller` quando arrancar |
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

### ADR-004 — Missão de picking com plataforma de destino por linha

- **Contexto:** inspirado em sistemas de picking de grandes armazéns
  (IKEA, Amazon, DHL): picking em lote, onde um operador serve várias
  encomendas ao mesmo tempo numa só passagem pelo armazém.
- **Decisão:** o `orchestrator` expõe as tarefas de picking como
  linhas de uma **missão** (`GET /api/picking/mission` para o resumo,
  `GET /api/picking/tasks` para as linhas), cada linha com um campo
  `plataforma` — o tote/palete de destino do artigo. O frontend abre
  sempre na primeira linha pendente, confirma e avança automaticamente
  ao atingir a quantidade alvo, e mostra o progresso da missão inteira
  (não só da linha corrente).
- **Porquê:** sem indicar o destino por linha, misturar artigos de
  encomendas diferentes no mesmo carrinho é o erro mais comum deste
  tipo de picking. Mostrar apenas o progresso da missão (não da tarefa
  isolada) e avançar sozinho entre linhas elimina decisões e toques
  desnecessários do operador (ver secção 4.3).
- **Consequência:** `transporte` e `abastecimento` devem seguir o
  mesmo padrão de missão quando forem implementados, adaptado ao que
  cada um move (paletes, localizações a repor).

### ADR-005 — Um único projeto `pda`, módulos internos

- **Contexto:** o `pda` cresceu de um módulo (`picking`) para três
  (`picking`, `transporte`, `abastecimento`), cada um atrás de
  login → módulos → zona. Ponderou-se ter um projeto/repo por módulo,
  coordenados por uma app "WOPA-PDA" externa.
- **Decisão:** os três módulos vivem dentro de **um único projeto**
  `pda` (`pda/src/modules/picking`, `.../transporte`,
  `.../abastecimento`), partilhando shell (login, sessão, seleção de
  zona) e cliente de API (`pda/src/shared`).
- **Porquê:**
  - É um único PWA instalado no dispositivo — um ícone, uma sessão,
    um service worker. Três apps separadas significam três instalações
    e três atualizações independentes no mesmo dispositivo.
  - Login, sessão, zona e cliente API são código genuinamente
    partilhado pelos três módulos; projetos separados obrigariam a
    triplicar isto ou a criar uma biblioteca partilhada só para isso.
  - Um único build estático para publicar no IIS.
- **Alternativa descartada:** um projeto "WOPA-PDA" que chama os
  módulos como apps/repos separados (estilo micro-frontend) —
  complexidade de integração (auth entre origens, versões a coordenar)
  sem benefício real ao tamanho atual da equipa/projeto.
- **Reavaliar quando:** um módulo crescer o suficiente para precisar
  de um ritmo de releases independente dos outros — nessa altura
  separa-se, não antes.

### ADR-006 — `controller` e `core-config` também em TypeScript + React + Vite

- **Contexto:** `controller` e `core-config` correm em Windows, não em
  PDA — a regra da ADR-002 (Android → PWA) não os obriga tecnicamente.
  Pesou-se manter .NET MAUI/Blazor Hybrid como stack de desktop
  separada.
- **Decisão:** `controller` e `core-config` são construídos na mesma
  stack do `pda` — **TypeScript + React + Vite** — como apps web
  separadas (não módulos dentro do `pda`, ver secção 3.4), com layout
  desktop em vez de mobile-first.
- **Porquê:**
  - **Uma só stack de frontend em todo o WOPA**: mesma linguagem,
    mesmas ferramentas de build/teste, potencial para partilhar
    componentes e o cliente de API com o `pda`.
  - O `controller` é essencialmente dashboards, tabelas e formulários
    (gestão de missões/ondas, configuração) — exatamente onde React é
    forte; não há requisito real de acesso ao SO que só uma app nativa
    desse.
  - Hospeda-se como ficheiros estáticos no mesmo IIS, coerente com a
    regra de infraestrutura on-premise.
  - **Hardware (leitores e impressoras) não é bloqueio** — ver secção
    3.6: leitores USB funcionam em modo teclado como qualquer input
    web; impressoras em rede são o `orchestrator` a imprimir; impressoras
    USB/série usam WebUSB/WebSerial (suportado em Chrome/Edge).
- **Risco aceite:** se algum dia surgir uma necessidade genuína de
  acesso ao SO que a Web API do browser não cubra (ex.: um periférico
  muito específico sem modo teclado nem WebUSB), reavalia-se nessa
  altura — não há indicação disso agora.

---

## 8. Em aberto

- Autenticação/autorização entre clientes e o `orchestrator` (ex.: JWT
  emitido pelo `orchestrator`, um por dispositivo/utilizador; login do
  operador no PDA hoje não é validado no backend).
- Se `packing` precisa de funcionar offline (ligação instável no
  armazém) — decide entre Blazor Server e WASM.
- Desenho do esquema inicial da base de dados WOPA (schemas por
  módulo, tabelas de picking/abastecimento/transporte, e de onde vêm
  as missões reais criadas pelo `controller`).
- Estratégia de sincronização/offline para os PDAs quando a rede
  Wi-Fi do armazém falha (fila local + reenvio, ou bloquear leitura
  até haver ligação?).
- Módulos `transporte` e `abastecimento`: desenhar o que cada um move
  e que "missão" faz sentido para cada um.
