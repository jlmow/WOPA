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

    ordershub["OrdersHub\n(existente)\npedidos de separação\n-> Ordens de Separação"]
    phc["PHC\n(ERP do cliente)"]

    controller -- REST/JSON --> orchestrator
    coreconfig -- REST/JSON --> orchestrator
    packing -- REST/JSON --> orchestrator
    pda -- REST/JSON --> orchestrator

    orchestrator --> db
    ordershub -- "POST /api/ordens-separacao (ADR-011)" --> orchestrator
    orchestrator <-- integração --> phc
```

**Princípio inegociável:** nenhum cliente fala diretamente com a base
de dados ou com sistemas externos. Tudo passa pelo `orchestrator` —
incluindo o `controller`, que **não tem acesso a bases de dados
externas** (é só frontend, ver ADR-006). Para as Ordens de Separação
(PHC/OrdersHub) o sentido é o inverso de uma consulta: é o WOPA que
**recebe**, através de um endpoint próprio do `orchestrator` — ver
ADR-011.

---

## 2. Módulos

| Módulo | Tipo de posto de trabalho | Responsabilidade |
|---|---|---|
| `orchestrator` | Servidor (sem UI) | "Cérebro": API REST/JSON central, regras de negócio, integração com o ERP (PHC), e receção das Ordens de Separação (`POST /api/ordens-separacao`) — ver secção 4.4/ADR-008/ADR-011 |
| `controller` | Desktop (Windows) | Consola de controlo/gestão operacional; lê as Ordens de Separação (via `orchestrator`) e cria as missões que o `pda` consome — ver secção 4.4/ADR-008 |
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
`orchestrator` distribui-as aos PDAs — ver 4.4 para o circuito completo.

### 4.4 Circuito completo: de onde vem uma missão até ao PDA

Confirmado pelo cliente:

```
OrdersHub / PHC                          orchestrator                    controller                    pda
────────────────                         ────────────                    ──────────                    ───
pedido de separação
        │
        ▼
"Ordens de Separação" ──POST /api/ordens-separacao──▶  guarda (ADR-011)
   (documento)                                                │
                                                                ▼
                                                          lê Ordens   ──cria missão──▶  distribui   ──1 missão──▶  executa
                                                          pendentes         (regras de       a missão                (offline-first,
                                                                            negócio,                                 ADR-007)
                                                                            ADR-010,
                                                                            a confirmar)
```

1. **Origem:** os pedidos de separação são feitos no **OrdersHub**
   (software já existente do cliente), que gera o documento
   **"Ordens de Separação"**.
2. **Entrada no WOPA — é o WOPA que recebe, não vai à procura
   (ADR-011):** independentemente de quem exatamente as envia (PHC ou
   OrdersHub — por confirmar, ver secção 8), a informação chega por
   `POST /api/ordens-separacao` no `orchestrator`. Não há consulta
   direta a nenhuma base de dados externa — nem do `orchestrator`, nem
   muito menos do `controller` (que é só frontend, sem acesso a bases
   de dados externas, ADR-006).
3. **Criação da missão:** o `controller`, a partir das Ordens de
   Separação recebidas (via API do `orchestrator`), cria as missões —
   segundo as `RegrasMissao` (ADR-010, ainda uma versão básica
   proposta, não confirmada) e regras de negócio adicionais que o
   cliente vai detalhar (ver secção 8). Ainda não implementado — o
   endpoint do ADR-011 só recebe e guarda por agora.
4. **Distribuição ao PDA — uma missão de cada vez:** as missões vão
   para os PDAs **uma a uma**, não em lote. Um PDA só tem **uma missão
   ativa localmente**. Ao terminá-la, vai buscar a seguinte — não
   descarrega a fila toda de antemão.
5. **Fronteira online/offline, agora mais precisa (refina o ADR-007):**
   - **A executar uma missão** (ler códigos, avançar linhas): pode
     estar offline — é exatamente o que o ADR-007 cobre.
   - **A começar uma missão nova, ou a terminar a atual e ir buscar a
     seguinte:** exige **ligação garantida ao servidor**. Não é o
     mesmo "talvez esteja online" do `navigator.onLine` do browser —
     ver ADR-009.

Ver ADR-008 para a decisão formal desta fronteira e ADR-009 para como
o `pda` verifica ligação de forma fiável.

### 4.5 Princípios de UX para PDA — picking orientado a performance

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
| `pda` — offline-first (`picking`) | ✅ PoC funcional | IndexedDB + fila de saída, testado com corte de rede real (ADR-007) |
| `pda` — indicador de ligação real | ✅ PoC funcional | Verificação por `/health`, presente em todos os ecrãs (ADR-009) |
| `pda` — módulos `transporte`, `abastecimento` | ⏳ Por começar | Já aparecem no seletor de módulos como "em breve"; seguem a mesma stack e os mesmos princípios de UX do `picking` |
| `controller` | 🚧 Em construção | Scaffold TypeScript/React/Vite, layout desktop (ver ADR-006) |
| `core-config` | ⏳ Por começar | Segue a mesma stack do `controller` quando arrancar; vai ser onde as `RegrasMissao` (ADR-010) passam a ser editáveis |
| `packing` | ⏳ Por começar | |
| Regras de missão configuráveis | ✅ PoC funcional | `GET`/`PUT /api/config/regras-missao` no `orchestrator`, ainda em memória (ADR-010) |
| Receção de Ordens de Separação | ✅ PoC funcional | `POST`/`GET /api/ordens-separacao` no `orchestrator`, testado; só recebe e guarda — ainda não cria missões (ADR-011) |
| Base de dados WOPA (SQL Server) | ✅ Script pronto | `orchestrator/database/schema.sql` — schema completo (inclui terminais, utilizadores, alvéolos, cestos, tipos de plataforma, stock — ADR-011), ainda **não ligado** ao `orchestrator` (que continua em memória na PoC) |
| Deployment (IIS, instalação no PDA) | ✅ Documentado | `orchestrator/DEPLOY.md`, `pda/INSTALAR-NO-PDA.md` — não executado por mim (sem acesso ao servidor/dispositivo do cliente) |

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
  desnecessários do operador (ver secção 4.5).
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

### ADR-007 — PDA offline-first: dados locais + fila de saída

- **Contexto:** requisito confirmado do cliente — os PDAs têm de
  continuar operacionais sem ligação ao `orchestrator`/BD (Wi-Fi fraco
  ou inexistente em partes do armazém). Até aqui, o `pda` dependia de
  uma chamada de rede bem-sucedida por cada leitura.
- **Decisão:** o módulo `picking` do `pda` passa a **local-first**:
  1. **Fonte de verdade no ecrã = base de dados local no dispositivo**
     (IndexedDB, via Dexie), não a resposta da API. A missão e as suas
     linhas são gravadas localmente assim que chegam do `orchestrator`.
  2. **Validação da leitura acontece no cliente**, comparando o código
     lido com o `codigoBarras` já guardado localmente — o dispositivo
     não precisa de perguntar ao servidor se uma leitura está certa.
     O ecrã atualiza-se de imediato, sempre, com ou sem rede.
  3. Cada leitura/confirmação gera uma entrada numa **fila de saída
     (outbox)** local, com um `operacaoId` gerado no dispositivo.
  4. Um processo de sincronização **drena a fila pela ordem em que
     foi criada** sempre que há rede (evento `online`, verificação
     periódica, e ao abrir o módulo) — envia cada operação ao
     `orchestrator` com o seu `operacaoId`, remove da fila quando o
     servidor confirma.
  5. O `orchestrator` aceita esse `operacaoId` e é **idempotente**:
     reenviar a mesma operação (ex.: por causa de uma resposta perdida
     em trânsito) devolve o mesmo resultado, sem duplicar o efeito.
- **Porquê este desenho e não outro:** é o padrão estabelecido para
  apps "local-first" (Dexie/IndexedDB + outbox é texto de manual, não
  invenção nossa); e o `picking` já tinha sido desenhado à volta de
  "o ecrã reage à leitura, não a uma resposta de rede" (ver secção
  4.5) — passar a validação e a atualização do ecrã para o cliente é
  uma extensão natural desse princípio, não uma reformulação.
- **Consequência para o backend:** qualquer endpoint de escrita
  chamado pelos PDAs (`scan`, `confirm`, e os equivalentes futuros de
  `transporte`/`abastecimento`) tem de aceitar um `operacaoId` opcional
  e ser seguro para reenviar — não é opcional projeto a projeto, é uma
  regra para qualquer escrita vinda de um PDA.
- **O que fica de fora desta primeira versão (limitações aceites):**
  - **Início de missão exige rede pelo menos uma vez** — um
    dispositivo que nunca sincronizou não tem o que picar em cache. Na
    prática isto não é problema: o operador começa o turno com rede
    (zona de docas/escritório) e só depois entra em zonas de sombra.
  - **Resolução de conflitos é mínima**: se uma operação em fila
    falhar por razão de negócio ao sincronizar (ex.: a missão foi
    cancelada entretanto no `controller`) — caso raro dado que só um
    operador trabalha uma missão de cada vez — a entrada é
    descartada da fila com aviso em consola; não há ainda um ecrã de
    "resolver conflito" para o operador ou supervisor. A registar como
    trabalho a fazer se/quando isto se mostrar necessário na prática.
  - **Login continua sem validação real no backend** (ver "Em
    aberto") — não faz parte deste ADR.
- **Reavaliar quando:** `transporte`/`abastecimento` chegarem a este
  ponto — aplica-se o mesmo padrão (secção 4.2/4.5 e este ADR também
  os cobre), não é uma decisão a repetir por módulo.

### ADR-008 — Ciclo da missão: OrdersHub → controller → orchestrator → PDA, uma missão de cada vez

- **Contexto:** o cliente esclareceu o circuito real de dados (ver
  secção 4.4): os pedidos de separação nascem no **OrdersHub**
  (existente), que gera as **Ordens de Separação**; essas Ordens
  chegam ao WOPA; o `controller` cria as missões a partir delas; os
  PDAs recebem-nas **uma de cada vez**, não em lote.
- **Decisão:**
  1. **Atualizado pelo ADR-011:** independentemente da origem (PHC ou
     OrdersHub), é o **WOPA que recebe** — não o `orchestrator` que vai
     consultar. Ver ADR-011 para o endpoint e o porquê deste desenho
     (mais simples e mais robusto que o `orchestrator` ir "à procura").
  2. O `controller` cria as missões a partir das Ordens de Separação
     recebidas (regras de negócio por confirmar — ver secção 8).
  3. O `orchestrator` entrega **uma missão de cada vez** a cada PDA. O
     dispositivo só mantém localmente a missão que está a executar.
  4. **Executar** uma missão pode ser feito offline (ADR-007).
     **Transicionar** entre missões — pedir a primeira, ou terminar a
     atual e pedir a seguinte — **exige ligação garantida ao
     servidor**, incluindo a fila de saída dessa missão
     completamente vazia (tudo sincronizado) antes de avançar.
- **Porquê:** manter a base de dados local e a fila de sincronização
  de cada PDA pequenas (uma missão, não um backlog inteiro) — reduz o
  volume de dados a sincronizar e o risco de conflito. E se um
  dispositivo vai buscar/entregar uma missão, faz sentido que esse seja
  precisamente o momento em que sabemos, com confiança, que há ligação.
- **Consequência:** o ecrã de "missão concluída" do `picking` só
  permite avançar (voltar aos módulos / ir buscar a próxima, quando essa
  funcionalidade existir) quando a ligação está confirmada e não há
  operações pendentes por sincronizar — ver ADR-009 para a verificação
  de ligação e a implementação atual desse bloqueio.
- **Por implementar** (ver secção 8): quem exatamente chama o endpoint
  do ADR-011 (PHC ou OrdersHub, e como), a criação de missões no
  `controller` segundo as regras de negócio do cliente a partir das
  Ordens de Separação recebidas, e um endpoint no `orchestrator` para
  "próxima missão" — hoje a PoC só tem uma missão fixa.

### ADR-009 — Indicador de ligação ao servidor, real, em todos os ecrãs do PDA

- **Contexto:** pedido explícito do cliente: todos os ecrãs do `pda`
  devem mostrar o estado atual de ligação ao servidor.
- **Decisão:** `navigator.onLine` do browser **não chega sozinho** —
  reflete a interface de rede do sistema operativo, não se o
  `orchestrator` está mesmo acessível (pode haver Wi-Fi ligado mas o
  servidor em baixo, ou numa VLAN sem rota até lá). O `pda` faz um
  pedido leve e periódico a `GET /health` no `orchestrator`; só
  considera "ligado ao servidor" quando esse pedido responde. O
  indicador vive num layout partilhado por cima de todas as rotas
  (login, módulos, zona, e cada módulo), não só dentro do `picking`.
- **Porquê:** "estado de ligação ao servidor" foi o termo usado pelo
  cliente — é uma verificação mais forte e mais honesta do que
  assumir que "rede ligada" implica "servidor alcançável".

### ADR-010 — Regras de criação de missão configuráveis (versão básica)

- **Contexto:** o cliente pediu explicitamente que as regras de como o
  `controller` monta missões a partir das Ordens de Separação sejam
  alteráveis a partir do `core-config`, e autorizou avançar com uma
  proposta básica sem esperar pelas regras reais.
- **Decisão:** um conjunto mínimo de regras, guardado como
  configuração (não código): `MaxLinhasPorMissao`,
  `MaxPlataformasPorMissao`, `CriterioAgrupamento` (Zona / Encomenda /
  Nenhum) e `CriterioOrdenacao` (Localizacao / Prioridade). Exposto
  pelo `orchestrator` em `GET`/`PUT /api/config/regras-missao`,
  persistido em `orchestrator.RegrasMissao` no schema SQL (ver
  `database/schema.sql`). Hoje só valida (`MaxLinhas`/`MaxPlataformas`
  ≥ 1); ainda não há um motor de criação de missões a consumir estas
  regras, porque isso depende de sabermos como as Ordens de Separação
  chegam (ADR-008) — falta esse elo antes de a configuração ter algo
  real para influenciar.
- **Porquê estes campos e não outros:** são os parâmetros mais óbvios
  para controlar o tamanho/complexidade de uma missão de picking em
  lote (nº de linhas, nº de plataformas de destino, como agrupar e
  ordenar) — mas são propostos por mim como ponto de partida razoável,
  **não** confirmados pelo cliente. Espera-se que mudem quando as
  regras de negócio reais chegarem.
- **Consequência:** o `core-config` (ainda por começar) terá aqui o
  seu primeiro ecrã real quando arrancar — editar este mesmo endpoint,
  não uma funcionalidade nova a inventar depois.

### ADR-011 — Receção de Ordens de Separação por endpoint (push, não pull), e modelo de dados de armazém

- **Contexto:** o cliente clarificou dois pontos importantes:
  1. Independentemente da origem exata (PHC ou OrdersHub), é o WOPA
     que **recebe** a informação — não o `orchestrator` a ir consultar
     uma BD externa. O WOPA expõe um endpoint; quem tiver essa
     informação escreve-a lá. O trabalho do `controller` (criar
     missões) começa a partir do que ficar guardado nessa tabela.
  2. O modelo de dados de armazém tem entidades obrigatórias que ainda
     não existiam no schema: **Terminais** (PDAs), **Utilizadores**
     (operadores), **Alvéolos** (localizações), **Cestos** (tipo de
     contentor, dimensões, quantos cabem numa palete), **Tipos de
     Plataforma** (P0/P1/P2/P4, dimensões/altura), **Movimentos de
     Stock** e **Stock por Armazém/Alvéolo** (com **Códigos de
     Movimento** — regra do cliente: `CM_ID < 500` é entrada,
     `CM_ID > 500` é saída).
- **Decisão:**
  1. `POST /api/ordens-separacao` no `orchestrator` recebe um
     documento (nº, origem, linhas de artigo/quantidade/alvéolo) e
     guarda-o — quem chama (PHC diretamente? um conector do
     OrdersHub?) ainda está por confirmar, mas a forma de entrada no
     WOPA já não depende dessa resposta.
  2. `database/schema.sql` passa a ter as tabelas
     `orchestrator.Terminais`, `.Utilizadores`, `.Alveolos`, `.Cestos`,
     `.TiposPlataforma`, `.CodigosMovimento`, `.MovimentosStock`,
     `.StockArmazem`, e `.OrdensSeparacao`/`.OrdensSeparacaoLinhas`.
     `picking.MissaoLinhas` passa a referenciar `AlveoloId` (em vez de
     um texto livre de localização) e `TipoPlataformaCodigo`, e ganha
     `CestoId`/`CestosNecessarios`. `picking.Missoes` passa a
     referenciar `UtilizadorId`/`TerminalId` em vez de texto livre.
  3. A regra `CM_ID < 500`/`> 500` está refletida numa coluna
     calculada (`Tipo`) em `orchestrator.CodigosMovimento`, não só em
     comentário — para não depender de cada consumidor da tabela
     acertar a regra da mesma forma.
- **Porquê "push" em vez do `orchestrator` consultar PHC/OrdersHub:**
  mais simples (o WOPA não precisa de saber onde/como consultar cada
  sistema externo, nem geri credenciais para lá), mais robusto (não há
  polling a falhar silenciosamente), e mantém o princípio da secção 1
  — o WOPA só fala com o mundo exterior através de um contrato de API
  próprio, nunca a espreitar bases de dados de terceiros.
- **Por implementar:** o motor que lê `OrdensSeparacao` pendentes e
  aplica as `RegrasMissao` (ADR-010) para criar `Missoes` de facto — o
  endpoint só recebe e guarda, ainda não processa. O `orchestrator`
  continua em memória (não ligado a `schema.sql`), por isso este
  endpoint hoje não persiste nada entre reinícios — ver secção 8.
- **Riscos aceites:** as dimensões de cestos/plataformas no seed são
  valores de exemplo (não confirmados); o campo `AlveoloCodigo` de uma
  linha recebida é opcional porque nem toda origem o vai ter disponível
  — o `controller` terá de decidir o alvéolo real ao montar a missão
  quando não vier preenchido.

---

## 8. Em aberto

- Autenticação/autorização entre clientes e o `orchestrator` (ex.: JWT
  emitido pelo `orchestrator`, um por dispositivo/utilizador; login do
  operador no PDA hoje não é validado no backend).
- Se `packing` precisa de funcionar offline (ligação instável no
  armazém) — decide entre Blazor Server e WASM.
- Ligar o `orchestrator` de facto ao SQL Server (`database/schema.sql`
  já existe como schema-alvo — falta o `orchestrator` passar de dados
  em memória para EF Core/Dapper a sério contra essa base de dados).
- Módulos `transporte` e `abastecimento`: desenhar o que cada um move
  e que "missão" faz sentido para cada um — e aplicar-lhes o mesmo
  padrão offline-first do ADR-007.
- Ecrã de resolução de conflitos de sincronização (ver limitações do
  ADR-007) — só vale a pena desenhar se se mostrar necessário na
  prática.
- Limite de armazenamento local do IndexedDB e política de limpeza de
  missões antigas já sincronizadas no dispositivo.
- **PHC vs. OrdersHub** (ADR-008/011): já não é "quem se consulta" —
  passou a "quem chama" `POST /api/ordens-separacao`. Falta confirmar
  se é o PHC, o OrdersHub, ou os dois, e se é uma integração direta ou
  passa por um conector/middleware intermédio.
- **Regras de negócio para criação de missões no `controller`**
  (ADR-008) — já há um mecanismo básico de configuração (ADR-010),
  mas os valores/critérios reais e o motor que efetivamente cria
  missões a partir de Ordens de Separação ainda faltam.
- **`database/schema.sql` ainda não foi executado contra um SQL
  Server real** (não há instância disponível neste ambiente de
  desenvolvimento) — a sintaxe segue os padrões standard do T-SQL, mas
  vale a pena correr uma primeira vez com atenção e confirmar antes de
  confiar nele em produção.
- Endpoint no `orchestrator` para "próxima missão" por
  operador/zona/dispositivo — hoje a PoC só serve uma missão fixa;
  falta decidir o critério de atribuição (fila simples? prioridade?
  por zona do operador?).
