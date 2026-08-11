# WOPA — Documento de Arquitetura

| | |
|---|---|
| **Estado** | Em desenvolvimento — validado com PoC funcional |
| **Última atualização** | Capacidades P1/P2/P4 (384/192/96 L) validadas contra 18 meses de dados reais e contra a query de produção do cliente — ver ADR-018 |
| **Âmbito** | Todos os módulos do projeto WOPA (Warehouse Order & Picking Automation) |
| **Fonte de negócio autoritativa** | `Requisitos Funcionais, Desenho da Solução e Arquitectura — WOPA v0.4` (agosto 2026), fornecido pelo cliente. Onde este documento e as decisões anteriores registadas aqui entrarem em conflito, **o v0.4 vence** — exceto nos dois pontos explicitamente revistos no ADR-015 (stack do PDA e fronteira de escrita) |

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
        packing["packing\n(POS, PWA — TypeScript + React + Vite)"]
        pda["pda\n(Android, PWA — login → módulos → zona)\npicking · transporte · abastecimento"]
    end

    subgraph Servidor["Servidor do cliente (on-premise, IIS)"]
        orchestrator["orchestrator\nASP.NET Core Web API\n(\"Cérebro\")"]
        db[("SQL Server\nWOPA")]
    end

    ordershub["OrdersHub\n(existente)\ncompõe as Ordens de Preparação"]
    phc["PHC\n(ERP do cliente)"]

    controller -- REST/JSON --> orchestrator
    coreconfig -- REST/JSON --> orchestrator
    packing -- REST/JSON --> orchestrator
    pda -- REST/JSON --> orchestrator

    orchestrator --> db
    ordershub -- "POST /api/ordens-preparacao (ADR-011/017)" --> orchestrator
    orchestrator <-- integração --> phc
```

**Princípio inegociável:** nenhum cliente fala diretamente com a base
de dados ou com sistemas externos. Tudo passa pelo `orchestrator` —
incluindo o `controller`, que **não tem acesso a bases de dados
externas** (é só frontend, ver ADR-006). Para as Ordens de Preparação
(PHC/OrdersHub) o sentido é o inverso de uma consulta: é o WOPA que
**recebe** — já compostas, prontas a tratar das etapas seguintes —
através de um endpoint próprio do `orchestrator` — ver ADR-011/017.

---

## 2. Módulos

Nomenclatura de aplicações confirmada pelo documento de requisitos
v0.4 ("sete aplicações em três camadas") — mapeada para os projetos
já existentes neste repositório:

| Módulo | Tipo de posto de trabalho | Responsabilidade (v0.4, seção 6.1) |
|---|---|---|
| `orchestrator` | Servidor (sem UI) | **WOPA Orchestrator**: "automação sem intervenção" — pull das células (ADR A.11), tipificação e cubicagem (Anexo A), sequenciamento de missões, geração de tarefas, e integração de fronteira com o OH/ERP (receção de Ordens de Preparação já compostas, `POST /api/ordens-preparacao`, ADR-017). Continua o **único ponto de escrita** na base de dados — ver ADR-015 |
| `controller` | Desktop (Windows) | **WOPA Controller**: coordenação humana — tipificação e despacho de plataformas, atribuição a células, prioridades, gestão de missões incompletas, monitorização integrada. Perfil único de utilizador (supervisor do CL); não precisa de acesso ao ERP para operar. *(A composição de Ordens de Preparação é feita fora do WOPA — ver ADR-017.)* |
| `core-config` | Desktop (Windows) | **WOPA Core/Config**: biblioteca central com as regras replicáveis (tipificação, cubicagem, empilhamento, slotting, agrupamento — Anexo A) e o painel de parametrização que as alimenta. Regras e parâmetros mantidos separados internamente |
| `packing` | Posto fixo tipo POS | **WOPA Packing**: posto de célula — conferência por modo (cestos/caixas), montagem da palete final por índice de camada, etiquetagem por cesto. O fecho de uma plataforma dispara o pull da seguinte (ADR A.11) |
| `pda` | PDA Android (mobilidade) | Um único projeto (ADR-005) com três módulos correspondentes às três apps do v0.4: **PDA Picking** (man-up — execução/validação de picks, implementado), **PDA Transporte** (transporte perpendicular de plataformas entre corredores e células, por implementar), **PDA Abastecimento** (put-away, abastecimento de topos, fluxo P0, por implementar) — ver secção 4.1 e ADR-015 (mantém-se PWA própria, não Kalipso Studio) |

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
| `packing` | **TypeScript + React + Vite** (PWA), hospedado em IIS — ver ADR-006 | Posto fixo tipo POS; mesmo argumento do `pda`: leitor em modo teclado, sem SDK nativo, e agora **uma única stack de frontend em todo o WOPA**, sem exceção |
| `pda` (módulos `picking`, `transporte`, `abastecimento`) | **PWA — TypeScript + React + Vite** (ver ADR-002) | Instalável no Android, sem SDK nativo, testável de ponta a ponta, atualização centralizada |
| Base de dados | 1 SQL Server ("WOPA"), **um único schema (`dbo`)** — ver ADR-003 | Simplicidade de gestão; muitas tabelas de referência são partilhadas entre módulos, não pertencem a um só |

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

1. **Login** — número de operador + PIN (ver ADR-013: login é
   obrigatório como primeiro ecrã em **todo** o software WOPA, não só
   no `pda`). Hoje o `pda` só pede o número, sem pedir/validar o PIN
   ainda — falta ligar a validação a sério ao `orchestrator`/tabela
   `US`, ver secção 8.
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

Confirmado pelo cliente (corrigido em ADR-017 — a composição da
Ordem de Preparação acontece **fora** do WOPA):

```
OrdersHub / PHC                    orchestrator                       controller                       pda
────────────────                   ────────────                       ──────────                       ───
compõe a Ordem de Preparação
(PS já agrupados por
cliente/data/morada)
        │
        ▼
POST /api/ordens-preparacao ──▶  guarda (ADR-017)
   (já composta)                        │
                                         ▼
                                   supervisor tipifica   ──gera Plataformas──▶  supervisor despacha
                                   (Anexo A.4/A.5)              (A.8)          (RF-CTL-06) ──cria missão──▶  ──1 missão──▶  executa
                                                                                                (RF-PIC-01)                  (offline-first,
                                                                                                                             ADR-007)
```

1. **Origem:** a composição da Ordem de Preparação (agrupar PS por
   cliente/data/morada, RF-CTL-02) acontece no **OrdersHub** (ou outro
   software do cliente) — **não no WOPA**.
2. **Entrada no WOPA — é o WOPA que recebe, já composta (ADR-017):**
   independentemente de quem exatamente a envia (PHC ou OrdersHub —
   por confirmar, ver secção 8), a informação chega por
   `POST /api/ordens-preparacao` no `orchestrator`, com os PS e as
   suas linhas já incluídos no pedido. Não há consulta direta a
   nenhuma base de dados externa — nem do `orchestrator`, nem muito
   menos do `controller` (que é só frontend, sem acesso a bases de
   dados externas, ADR-006).
3. **Tipificação e despacho:** o supervisor, no `controller`, tipifica
   a ordem recebida (cubica, escolhe o tipo de plataforma, gera as
   Plataformas — Anexo A.4/A.5/A.8) e despacha cada plataforma
   (atribui célula, RF-CTL-06) — o que gera a Missão de picking
   (RF-PIC-01). Feito manualmente, uma ordem/plataforma de cada vez
   (ver ADR-016/017); ainda não usa `RegrasMissao` (ADR-010) nem tem
   proposta automática.
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

### 4.6 Zonas do armazém físico e ordem de picking

Confirmado pelo cliente a partir da planta do armazém:

- **`OUTLET`**, **`ARMAZEM AUTOMATICO`** e **`ARMAZEM (ALVEOLOS)`** são
  exemplos de zonas reais (mais virão — o cliente vai enviar mais
  contexto). `ARMAZEM (ALVEOLOS)` tem o detalhe de alvéolo que já
  temos modelado; `ARMAZEM AUTOMATICO` **não tem** — para essa zona o
  `orchestrator` só manda "separar isto" sem indicar um alvéolo
  específico (é provavelmente um sistema automático próprio, tipo
  AS/RS, a decidir de onde tira o artigo). Refletido no schema:
  `MissaoLinhas.AlveoloId` passou a **NULL-ável** — deixou de
  fazer sentido obrigar todas as linhas a terem alvéolo.
- **Ordem de picking por defeito:** OUTLET primeiro, depois ARMAZÉM
  AUTOMÁTICO, depois ARMAZÉM (ALVÉOLOS). Mas o cliente foi explícito:
  este "sempre" é subjetivo — a ordem tem de ser **configurável e
  flexível**, não uma regra fixa no código. Isto entronca no mecanismo
  de `RegrasMissao` já existente (ADR-010): a ordem por zona é mais um
  parâmetro a acrescentar aí quando desenharmos o motor de criação de
  missões — ainda por implementar (ver secção 8), tal como o resto do
  motor que lê Ordens de Separação e aplica regras (ADR-011).
- **Por decidir, ainda sem informação suficiente:** se as linhas do
  `ARMAZEM AUTOMATICO` chegam sequer a um PDA (pode ser uma zona sem
  intervenção humana, gerida por um sistema automático que o WOPA só
  aciona) — a API já não rebenta com estas linhas (`Localizacao` fica
  `""` quando não há alvéolo), mas o comportamento correto no ecrã
  ainda não está definido.

### 4.7 Modelo de domínio real (documento de requisitos v0.4)

O documento de requisitos v0.4 fixa uma hierarquia de domínio mais
rica do que a modelada até aqui, com base em 18 meses de dados reais e
147 PS analisados a fundo. **É autoritativa (ADR-015)** e substitui o
modelo informal usado nas seções 4.1–4.6 e no schema atual onde houver
conflito — ver secção 8 para o trabalho de schema ainda por fazer.

**Hierarquia:** `PS → Ordem de Preparação → Plataforma → Cesto → Missão`

| Conceito | Definição |
|---|---|
| **PS** (pedido de separação) | Unidade de contrato com o ERP. Sem limite de referências. Um PS pode gerar componente P0 (paletes completas) e componente de picking em simultâneo (regra A.3) |
| **Ordem de preparação** | Agrupamento de PS por cliente, data e morada de entrega. É a unidade que se cubica, se tipifica e se despacha. **Chega já composta de outro software** (ADR-017) — o WOPA recebe-a e guarda-a; não compõe PS em ordens |
| **Plataforma** | Veículo físico anónimo e fungível (estrado 120×80) que transporta o trabalho de picking pelos corredores até à célula. Tipada P4/P2/P1 pelos cestos que leva — **P0 não é um tipo de plataforma**, é um fluxo direto reserva→expedição para paletes completas (regra A.3), executado pelo empilhador de abastecimento, fora do circuito de corredores |
| **Cesto** | Contentor que segrega uma ordem de preparação dentro da plataforma. **Um cesto = uma ordem (invariante)**. Três tamanhos (P4/P2/P1); não se misturam tamanhos na mesma plataforma |
| **Missão** | Unidade de trabalho atribuída a um operador num centro de trabalho. Tipificada por centro: **picking, packing, transporte, abastecimento, reposição, P0** — não só picking, como modelado até agora |
| **Rota** | Agrupamento de expedição, possivelmente multicliente, que junta volumes já embalados para carregamento — ainda não modelado |

**Dois cenários de composição de plataforma (secção 4.2 do v0.4):**

- **Cenário A — ordens ≥ P1:** a ordem excede a capacidade de uma
  plataforma e reparte-se por *n* plataformas P1 (notação `P1(n)`).
  Cada plataforma é mono-ordem, mono-cliente. A sequência das
  plataformas obedece à restrição de empilhamento (ver abaixo).
- **Cenário B — ordens < P1:** várias ordens pequenas partilham a
  mesma plataforma para aproveitar a viagem pelos corredores — uma
  ordem por cesto. Podem ser de clientes/moradas/datas diferentes; a
  segregação é garantida pelo cesto, não pela plataforma.

**Dimensões e capacidades** — duas medidas distintas, não confundir
(ver ADR-018): a **altura física do cesto** (P1/P2/P4) é 0,40 m,
confirmada pelo cliente; a **altura útil de carga** para efeitos de
tipificação por volume é 0,50 m (o "limite de alcance do operador
sobre o cesto" do v0.4 — o operador enche acima do rebordo do cesto,
dentro do alcance) e é essa que a query real de tipificação do
cliente usa (limiares 96000/192000/384000 cm³, confirmados contra
dados reais). **P0 existe** como tipo de plataforma real — palete
completa, sem cestos, altura 1,30 m — não é um "fluxo sem tipo" como
uma leitura inicial do v0.4 sugeria (ver ADR-017):

| Tipo | C×L (cm) | Altura física (cm) | Altura útil de carga (cm) | Capacidade útil (L) | Cestos por plataforma |
|---|---|---|---|---|---|
| P0 | 120×80 | 130 | — | — (fluxo direto, sem tipificação por volume) | 0 |
| P1 | 120×80 | 40 | 50 | 384 | 1 (cesto = plataforma) |
| P2 | 60×80 | 40 | 50 | 192 | 2 |
| P4 | 40×60 | 40 | 50 | 96 | 4 |

Regra de tipificação (A.4): o tipo é o **menor cesto** onde o volume
de picking da ordem cabe — P4 até 96 L, P2 até 192 L, P1 até 384 L.
Acima disso, multi-plataforma `P1(n)`, `n = CEILING(vol / 384L)`,
sempre com plataformas P1 (mesmo quando o resto caberia num cesto
menor — simplicidade operacional). Cubicagem detalhada em A.1/A.2:
caixas completas pelo volume da caixa, avulsas por fração proporcional
(não ocupam caixa própria).

**Empilhamento da palete final (secção 4.3):** pesados em baixo, leves
em cima, padrão cíclico (1 camada pesada + N leves, N ainda por fixar
— ver "Em aberto"). Cada plataforma de uma ordem ≥P1 corresponde a uma
camada e traz um índice de sequência. O packing consome plataformas
por índice de camada, não por ordem de chegada — daí o buffer de 4
lugares à entrada da célula, que absorve a reordenação do circuito
(90% das ordens ≥P1 têm ≤4 plataformas e cabem inteiramente no
buffer). **O peso deixou de ser critério de dimensionamento** — dados
reais mostram plataformas a ~6% do limite de 1.200 kg; passa a
salvaguarda (A.15), não a regra de composição.

**Pull por buffer (secção 4.4/A.11):** não há células de consolidação
— a consolidação faz-se na separação. Todas as células são de
packing, em dois modos reconfiguráveis por parametrização: **modo
cestos** (ONLINE/ordens pequenas, conferência EAN artigo a artigo) e
**modo caixas** (B2B/FISICAS/CNUS, conferência mais leve de plataformas
de caixas fechadas mono-cliente). Cada célula tem buffer de 4 lugares;
ao libertar um lugar, puxa automaticamente a próxima plataforma
destinada a essa célula.

**Missões incompletas:** uma missão pode ficar aberta e incompleta
(tipicamente por rutura de stock na frente) com motivo tipificado
(rutura, fim de turno, mudança de prioridade, avaria). A plataforma
segue e a ordem fica parcialmente satisfeita. **O fecho é sempre
decisão do supervisor no `controller`** — fechar, retomar ou
reatribuir (A.13). Isto generaliza o que já tínhamos como "pausa" só
para picking.

**Canais (secção 2.1)** — cada um com perfil de composição diferente,
relevante para o motor de missões (`RegrasMissao`, ADR-010):

| Canal | Perfil |
|---|---|
| ONLINE | E-commerce. Pedido = encomenda = cliente. 54% das linhas fora do case pack (avulsas). 96% dos PS cabem num cesto |
| B2B | Retalho/grossista. Uma encomenda pode gerar vários PS. Maioritariamente caixas completas |
| FISICAS | Reposição de lojas próprias. ~30% das linhas com avulsas |
| CNUS | Cliente único de grande volume. Predomínio de paletes completas (fluxo P0). PS grandes, poucas linhas, muitas peças |

**Geometria física do CL (secção 2.2)** — dados confirmados no
levantamento, relevantes para o slotting (A.10) e o sequenciamento de
picks (A.9): 4 corredores de picking, 8 laterais (2 por corredor), 7
níveis em altura, 51 alvéolos ao comprimento (2.856 frentes de picking
no total). Catálogo ativo (~5.500 refs) excede as frentes disponíveis
— falta regra de atribuição de frentes (ver "Em aberto"). Picking por
transelevadores man-up, um por corredor, que não saem do corredor;
transporte entre corredores/células por empilhador de transporte
perpendicular; abastecimento de topos, put-away e fluxo P0 por
empilhador dedicado. Racks de reposição de 9 andares, palete 80×120,
altura útil 115 cm, peso máx. 1.200 kg.

**Faseamento recomendado pelo v0.4 (secção 9):**

- **Fase 1 (MVP):** interface de entrada, modelo de localizações e
  stock, `controller` com composição de ordens e atribuição a células,
  tipificação P0/P1, missões de picking e transporte, packing em modo
  caixas, expedição. Fluxos B2B/FISICAS/CNUS.
- **Fase 2:** plataformas partilhadas (P4/P2) e composição por cesto,
  packing em modo cestos com conferência EAN, empilhamento por
  camadas, pull por buffer completo, slotting vertical, missões de
  abastecimento e reposição.
- **Fase 3:** plataforma órfã e edição de ordens em curso, painel de
  supervisão completo, contagens cíclicas, parametrização avançada,
  afinação com tempos reais medidos pelo próprio sistema.
- **Depois da fase 3:** integração com transportadoras.

O PoC de `picking` construído até agora cobre uma fatia vertical fina
de tipificação P1 simples (uma missão, um tipo), não ainda as
composições de plataforma partilhada nem o empilhamento — alinhado com
começar pela Fase 1 e crescer para a Fase 2.

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
| `orchestrator` — endpoints de picking, zonas, módulos | ✅ Ligado a SQL Server real | Já não é em memória — EF Core contra o schema de `database/schema.sql`, testado a sério (ver ADR-012) |
| `pda` — shell (login, módulos, zona) | ✅ PoC funcional | React Router com sessão local; módulos indisponíveis aparecem desativados |
| `pda` — módulo `picking` | ✅ PoC funcional | Fluxo guiado (auto-início, avanço automático, plataforma de destino, progresso da missão), testado de ponta a ponta com um browser real |
| `pda` — offline-first (`picking`) | ✅ PoC funcional | IndexedDB + fila de saída, testado com corte de rede real (ADR-007) |
| `pda` — indicador de ligação real | ✅ PoC funcional | Verificação por `/health`, presente em todos os ecrãs (ADR-009) |
| `pda` — módulos `transporte`, `abastecimento` | ⏳ Por começar | Já aparecem no seletor de módulos como "em breve"; seguem a mesma stack e os mesmos princípios de UX do `picking` |
| `controller` — Ordens de Preparação, Missões | ✅ PoC funcional, ponta a ponta | Dois ecrãs reais (não só leitura): tipificar (gera Plataformas) e despachar (gera Missão) Ordens de Preparação já recebidas de outro software, e gerir missões (pausar/retomar/fechar/reatribuir) — ver ADR-016/017. Testado com browser real contra SQL Server real |
| `core-config` | ⏳ Por começar | Segue a mesma stack do `controller` quando arrancar; vai ser onde as `RegrasMissao` (ADR-010) passam a ser editáveis |
| `packing` | ⏳ Por começar | |
| Regras de missão configuráveis | ✅ Persistido em SQL Server | `GET`/`PUT /api/config/regras-missao` no `orchestrator`, agora na tabela `RegrasMissao` (ADR-010/012) |
| Receção de Ordens de Preparação | ✅ Persistido em SQL Server | `POST`/`GET /api/ordens-preparacao`, recebe a ordem já composta com os PS aninhados (RF-ENT-01: cliente/canal/morada/data). Ganhou cubicagem/tipificação indicativa (RF-CTL-01) — ver ADR-016/017 |
| Cubicagem/tipificação (Anexo A) | ✅ PoC funcional | `CubicagemService`: A.1 (cubicagem de linha), A.2 (volume de ordem), A.4/A.5 (tipo + decomposição P1(n)), A.8 (índice de camada) — limiares lidos de `TiposPlataforma`, não hardcoded. Testado com SKUs reais |
| Ordem de Preparação → Plataforma → Missão | ✅ PoC funcional, ponta a ponta | `POST /api/ordens-preparacao` (recebe a ordem já composta, com PS aninhados), `POST .../tipificar` (gera Plataformas), `POST /api/plataformas/{id}/despachar` (gera Missão de picking) — ver ADR-016/017 |
| Missões — máquina de estados (A.13) | ✅ PoC funcional | `Criada → Atribuida → EmExecucao → (Pausada ↔ EmExecucao) → Concluida | FechadaIncompleta`, com motivo de pausa e timestamps; `pausar`/`retomar`/`fechar`/`reatribuir` em `/api/missoes` |
| `pda` — "próxima missão" | ✅ PoC funcional | `GET /api/picking/mission`/`tasks` resolvem dinamicamente a missão de picking mais antiga ainda ativa, em vez de uma fixa — testado com duas missões em fila |
| Base de dados WOPA (SQL Server) | ✅ Testada contra uma instância real | `orchestrator/database/schema.sql` corrido com sucesso, idempotente (SQL Server 2022 em Docker, usado só para validar neste ambiente de desenvolvimento — ver ADR-012/016). O `orchestrator` já lê/escreve nela via EF Core |
| Deployment (IIS, instalação no PDA) | ✅ Documentado, ⚠️ script não testado num Windows Server real | `orchestrator/DEPLOY.md`, `pda/INSTALAR-NO-PDA.md`, e agora `deploy/install-wopa.ps1` (instalação automática de ponta a ponta) — nada disto correu contra o servidor/dispositivo real do cliente (sem acesso); o `.ps1` foi validado por parsing sintático e pela lógica testável fora do Windows (geração de JSON/env, CORS), mas os cmdlets do IIS (`WebAdministration`) nunca correram a sério |
| Deploy direto do GitHub | ✅ Documentado | `.github/workflows/deploy.yml`, disparado manualmente (`workflow_dispatch`), corre num runner self-hosted no próprio servidor (sem acesso de entrada da internet — o runner liga-se para fora ao GitHub). Ver `orchestrator/DEPLOY.md` secção 0.1 para instalar o runner e configurar os secrets |

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

### ADR-003 — Uma base de dados, um único schema (atualizado)

- **Contexto:** requisito do cliente de uma única base de dados SQL
  Server ("WOPA") para todas as funcionalidades. A versão original
  desta decisão propunha um schema por módulo (`orchestrator`,
  `picking`, ...) — **o cliente pediu para reverter isso**: prefere
  trabalhar com um único schema. Motivo dado: mais simples de gerir na
  prática, sobretudo havendo **tabelas partilhadas entre aplicações**
  (`Zonas`, `TER`, `US`, `ALV`, etc. já são usadas por mais do que um
  módulo) — separar por schema criava fronteiras artificiais onde a
  realidade é de dados partilhados.
- **Decisão:** uma instância de SQL Server, **um único schema
  (`dbo`)**, todas as tabelas lá dentro. `database/schema.sql` e o
  `WopaDbContext` (EF Core) já refletem isto — sem prefixo de schema
  nos nomes das tabelas.
- **Porquê:** cumpre o requisito de BD única; simplicidade de gestão
  ganha à separação teórica por módulo, dado que a maior parte das
  tabelas de referência (zonas, terminais, utilizadores, alvéolos) são
  genuinamente partilhadas, não pertencem a um módulo só.

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
- **Atualização:** o `packing` (posto fixo tipo POS, antes cotado para
  Blazor) junta-se também a esta stack única — o cliente confirmou.
  Mesmo argumento de hardware da secção 3.6 (leitor em modo teclado)
  aplica-se; deixa de haver nenhuma app WOPA fora de TypeScript +
  React + Vite. Scaffold do `packing` ainda por fazer.

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
  persistido em `RegrasMissao` no schema SQL (ver
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
     `TER`, `.US`, `.ALV`, `.CESTOS`, `.TiposPlataforma`,
     `.CM`, `.SL`, `.SA`, e `.OrdensSeparacao`/`.OrdensSeparacaoLinhas`.
     `MISSAO` é o nome exato pedido pelo cliente para o
     cabeçalho da missão (`MissaoLinhas`, sem código pedido,
     manteve o nome descritivo). `MissaoLinhas` passa a
     referenciar `AlveoloId` (em vez de um texto livre de localização)
     e `TipoPlataformaCodigo`, e ganha `CestoId`/`CestosNecessarios`.
     `MISSAO` passa a referenciar `UtilizadorId`/`TerminalId`
     em vez de texto livre.
  3. A regra `CM_ID < 500`/`> 500` está refletida numa coluna
     calculada (`Tipo`) em `CM`, não só em comentário —
     para não depender de cada consumidor da tabela acertar a regra da
     mesma forma.
- **Porquê "push" em vez do `orchestrator` consultar PHC/OrdersHub:**
  mais simples (o WOPA não precisa de saber onde/como consultar cada
  sistema externo, nem geri credenciais para lá), mais robusto (não há
  polling a falhar silenciosamente), e mantém o princípio da secção 1
  — o WOPA só fala com o mundo exterior através de um contrato de API
  próprio, nunca a espreitar bases de dados de terceiros.
- **Por implementar:** o motor que lê `OrdensSeparacao` pendentes e
  aplica as `RegrasMissao` (ADR-010) para criar `MISSAO` de facto — o
  endpoint só recebe e guarda, ainda não processa. O `orchestrator`
  continua em memória (não ligado a `schema.sql`), por isso este
  endpoint hoje não persiste nada entre reinícios — ver secção 8.
- **Riscos aceites:** as dimensões de cestos/plataformas no seed são
  valores de exemplo (não confirmados); o campo `AlveoloCodigo` de uma
  linha recebida é opcional porque nem toda origem o vai ter disponível
  — o `controller` terá de decidir o alvéolo real ao montar a missão
  quando não vier preenchido.
- **Nomes de tabela exatos, por pedido do cliente:** `TER`, `US`,
  `ALV`, `CESTOS`, `MISSAO`, `SL`, `SA` e `CM` não são apelidos — são
  os nomes reais das tabelas em `orchestrator`/`picking`. As restantes
  tabelas (`Zonas`, `Modulos`, `RegrasMissao`, `OrdensSeparacao`,
  `MissaoLinhas`, `OperacoesProcessadas`, `TiposPlataforma`) mantêm
  nomes descritivos por não terem sido dado um código específico.
- **Tentativa inicial de ligar o `orchestrator` a SQL Server:** o pacote
  `mssql-server` do apt vem de um host geofenced
  (`pmc-geofence.trafficmanager.net`) bloqueado pela política de rede
  da sandbox onde isto foi escrito (não algo a contornar). A imagem
  Docker oficial (`mcr.microsoft.com/mssql/server`), em contrapartida,
  não estava bloqueada — resolvido ao correr um SQL Server 2022 em
  contentor Docker só para validar isto neste ambiente de
  desenvolvimento (não é o servidor do cliente).

### ADR-012 — Orchestrator ligado a SQL Server a sério: Opção A (API estável, schema normalizado por trás)

- **Contexto:** com o schema novo (ADR-011) a normalizar localização e
  tipo de plataforma em tabelas próprias (`ALV`, `TiposPlataforma`), o
  `pda` — já testado a fundo a consumir `localizacao`/`plataforma`
  como texto simples — ficava perante duas opções (colocadas ao
  cliente): (a) o `orchestrator` mantém a API simples e faz `JOIN` por
  trás; (b) muda-se a API e o `pda` para IDs normalizados. **O cliente
  escolheu a opção A.**
- **Decisão:** o `orchestrator` passa a usar **EF Core** ("database
  first" — mapeia para as tabelas já criadas por `database/schema.sql`,
  não usa migrations) como camada de acesso a dados, uma
  `WopaDbContext` com entidades para cada tabela do schema. Os
  endpoints (`/api/picking/*`, `/api/config/regras-missao`,
  `/api/ordens-separacao`, `/api/zonas`, `/api/modulos`) continuam a
  devolver **exatamente o mesmo formato JSON de antes** — o `PickingTask`
  (DTO da API) mantém `localizacao`/`plataforma` como texto; o `JOIN`
  para `ALV.Codigo` acontece só na fronteira da API
  (`PickingEndpoints.ParaDto`), nunca chega ao `pda`.
- **Idempotência sem snapshot (ADR-007 revisitado):** a versão em
  memória guardava uma cópia do resultado por `operacaoId`. A tabela
  real `OperacoesProcessadas` só regista *que* uma operação
  aconteceu (sem guardar o resultado) — por isso, ao detetar um
  reenvio, o `orchestrator` devolve o **estado atual** da linha em vez
  de um snapshot antigo. É mais simples e continua correto: como só um
  operador trabalha uma missão de cada vez (ADR-008), o estado atual
  já reflete o que essa operação fez.
- **Validado, não assumido:** corri `database/schema.sql` contra uma
  instância SQL Server 2022 real (Docker, só para teste), com sucesso
  à primeira depois de uma correção (`SET QUOTED_IDENTIFIER ON`,
  necessário para a coluna calculada de `CM` — só se descobriu ao
  correr a sério, prova de porque isto importa). Depois:
  - Todos os endpoints testados contra essa base de dados real.
  - **Reiniciei o processo do `orchestrator` por completo** e confirmei
    que os dados continuavam lá — prova de que é persistência real, não
    o mesmo processo em memória a continuar a correr.
  - Corri os testes Playwright já existentes do `pda` (offline
    completo, indicador de ligação, bloqueio de transição de missão) e
    do `controller` contra este `orchestrator` ligado à BD — todos a
    passar sem alterar uma linha de código dos frontends.
- **Para produção:** a connection string do contentor de teste
  (`appsettings.Development.json`) **não serve para nada em
  produção** — é preciso configurar `ConnectionStrings:Wopa` com o
  servidor real do cliente, via `appsettings.Production.json` ou a
  variável de ambiente `ConnectionStrings__Wopa` (ver
  `orchestrator/DEPLOY.md`). Continuo sem essa connection string real
  — só testei contra o contentor local.
- **Por implementar:** `SL`/`SA` (movimentos e stock) estão no schema
  mas nada ainda escreve lá — falta decidir quando um `scan`/`confirm`
  de picking deve gerar um movimento de stock. Login do `pda` continua
  sem validar `US.NumeroOperador` a sério (ver secção 8).

### ADR-013 — Login (user + PIN) obrigatório como primeiro ecrã, em todo o software

- **Contexto:** pedido explícito do cliente — tem de se saber sempre
  quem está a trabalhar em cada software WOPA, seja PDA ou Windows.
- **Decisão:** **todos** os frontends (`pda`, `controller`,
  `core-config`, `packing`) têm de abrir sempre no ecrã de login como
  primeiro passo, sem exceção — não há caminho para usar a app sem
  login. Esquema: **número de operador + PIN**, contra a tabela `US`
  (que já tem `NumeroOperador`; ganhou agora o campo `Pin`).
- **Estado atual:** só o `pda` tem ecrã de login, e mesmo esse só pede
  o número — não pede nem valida o PIN ainda, e não confirma contra a
  tabela `US` (aceita qualquer valor). `controller` e `packing` não
  têm login nenhum hoje. Fica tudo por implementar (ver secção 8).
- **Segurança do PIN (PoC vs. produção):** o campo `US.Pin` está em
  texto simples no schema, deliberadamente, para a fase de PoC. Antes
  de produção tem de ser guardado com hash (nunca texto simples) — a
  registar como passo obrigatório do trabalho de autenticação (ADR
  futuro quando o desenho de auth for feito a sério, ver secção 8).

### ADR-014 — Lógica de referência do PHC: cubicagem/plataforma e derivação de stock

- **Contexto:** o cliente enviou queries reais correndo hoje contra o
  PHC, que documentam duas peças de lógica de negócio que o WOPA tem
  de reproduzir ou substituir:
  1. **Necessidades de picking e tipificação de plataforma** — uma
     query sobre `bo`/`bi`/`st` (documentos com `ndos=209` ainda não
     processados) que agrupa por documento, calcula a cubicagem fiel
     (caixas completas + fração proporcional dos artigos avulsos) e
     classifica o resultado em plataformas — `P4`/`P2`/`P1`/`P1(n)` —
     por volume, sinalizando também artigos com ficha técnica
     incompleta (sem embalagem/dimensões/peso). É a lógica de origem
     do `ALV`/`CESTOS`/`TiposPlataforma`/ADR-004 já modelados.
  2. **Derivação de stock** — o PHC não guarda um saldo; deriva-o em
     leitura através de uma view, `uv_stkalvplt`, que soma movimentos
     (`sl`) com sinal invertido consoante o tipo de movimento (`cm`),
     filtrados a partir de uma data de corte e só para movimentos
     associados a uma palete, agrupados por artigo+armazém+palete+
     alvéolo — trazendo ainda atributos da palete (`fref`): código
     único, tipo, se está marcada, se pertence a uma palete "master"
     (com peso próprio), e o stamp do documento de origem.
- **Decisão:** tratar estas duas queries como **especificação
  funcional de referência**, não como desenho a copiar 1:1:
  1. A cubicagem/classificação de plataforma alimenta o motor de
     criação de missões ainda por construir (ver secção 8) — o
     resultado (que separar, para que plataforma) é o que chega ao
     WOPA. **Mantém-se a decisão já tomada no ADR-011: é o WOPA que
     recebe essa informação via `POST /api/ordens-separacao` (push);
     o `orchestrator` não passa a consultar o PHC diretamente.** Quem
     corre esta lógica de cubicagem antes de chamar o endpoint (o
     próprio PHC? um conector intermédio?) fica por confirmar — ver
     conflito abaixo.
  2. A derivação de stock por soma de movimentos é o mesmo princípio
     já modelado em `SL` (Movimentos de Stock) + `CM` (Código de
     Movimento, com a regra `CM_ID < 500` = entrada / `> 500` = saída)
     + `SA` (Stock por Armazém/Alvéolo) — **não** se introduzem tabelas
     novas (`palete`/`movimento_stock`/`stock_atual`); `SL`/`SA`/`CM`
     já são os nomes exatos pedidos pelo cliente (ADR-011) e cumprem o
     mesmo papel que `uv_stkalvplt`. `uv_stkalvplt` serve de
     especificação para a query/view equivalente a construir sobre
     `SL`/`SA` quando se implementar a escrita de movimentos (ainda
     por fazer, ver secção 8).
- **Conflito sinalizado aqui, entretanto resolvido pelo documento de
  requisitos v0.4 (ver ADR-015):** a query de cubicagem, tal como
  enviada, sugeria o `orchestrator` a ler diretamente tabelas do PHC
  (`bo`/`bi`/`st`) para calcular as necessidades — o que pareceria
  colidir com o princípio "push, não pull" do ADR-011. O v0.4 confirma
  que não há conflito: **RF-ENT-01/03** especificam que o WOPA
  **recebe** via integração com o ERP tanto os PS (canal, cliente,
  morada, data, linhas) como os **dados mestre de artigos**
  (unidades/caixa, dimensões, peso, classe de empilhamento) —
  suficiente para o `orchestrator` correr ele próprio a cubicagem
  (Anexo A.1–A.5) sem nunca consultar tabelas do PHC diretamente. A
  query `bo`/`bi`/`st` era só a forma como o PHC produz hoje essa
  informação do lado dele — não o desenho de integração do WOPA. O
  ADR-011 mantém-se tal como estava.
- **Porquê não copiar o schema de stock proposto (`palete`/
  `movimento_stock`):** o cliente já pediu, em mensagem própria e mais
  recente, nomes de tabela exatos — `SL`, `SA`, `CM` — com a regra de
  sinal via `CM_ID`. Introduzir tabelas paralelas com sinal
  pré-calculado duplicaria o mesmo conceito de forma incompatível.
  Prefiro reconciliar a lógica nova dentro do schema já acordado a
  arriscar dessincronizar os dois.

### ADR-015 — Adoção do documento de requisitos v0.4 como fonte autoritativa, com duas exceções explícitas

- **Contexto:** o cliente entregou `Requisitos Funcionais, Desenho da
  Solução e Arquitectura — WOPA v0.4`, um documento muito mais
  detalhado do que a informação fornecida até aqui: modelo de domínio
  completo (PS → Ordem de Preparação → Plataforma → Cesto → Missão),
  regras de negócio executáveis (Anexo A), resultados de simulação
  sobre dados reais, e uma proposta de arquitetura de software própria
  — incluindo stack tecnológica, que diverge em dois pontos do que já
  estava construído e testado neste repositório.
- **Decisão (confirmada pelo cliente, quatro perguntas diretas):**
  1. **O v0.4 é autoritativo.** Onde o modelo de domínio, as regras de
     negócio (Anexo A) ou os requisitos funcionais deste documento
     entrarem em conflito com decisões anteriores registadas aqui
     (nomes/hierarquia de entidades, dimensões de cesto, P0 como tipo
     de plataforma, regras de missão improvisadas), **o v0.4 vence**.
  2. **Exceção 1 — stack do PDA:** o v0.4 recomenda **Kalipso Studio**
     para as três apps de PDA. **Mantém-se a PWA TypeScript + React +
     Vite já construída e testada** (offline-first real, indicador de
     ligação real, ADR-002/005/007/009) — decisão do cliente, que
     prevalece sobre a recomendação do documento nesta área específica.
  3. **Exceção 2 — fronteira de escrita:** o v0.4 propõe *"stored
     procedures como fronteira de escrita para os PDA"*, o que lido à
     letra sugeriria PDAs a escrever direto no SQL Server. **Mantém-se
     o `orchestrator` como único gateway de escrita** (princípio da
     secção 1): o PDA continua a falar só com a API do `orchestrator`;
     o `orchestrator` pode (e deve, para honrar a recomendação do
     documento onde faz sentido) usar stored procedures **por baixo**
     da sua própria camada de acesso a dados, para a validação de
     estado/EAN/quantidade nas escritas de picking — mas nenhum
     cliente volta a tocar diretamente na base de dados.
  4. **Âmbito:** apesar do v0.4 sugerir os três PDA como "pacote bem
     delimitado, adequado a desenvolvimento externo", o âmbito deste
     trabalho **continua a incluir o `pda`** — não passa para uma
     equipa externa nem para Kalipso Studio.
- **Porquê:** o v0.4 é um documento de negócio produzido com dados
  reais (147 PS, simulação de 18 meses) — deve substituir modelação
  improvisada feita sem essa informação. As duas exceções protegem
  trabalho já validado (PoC offline-first testada com corte de rede
  real) e um princípio arquitetural já acordado explicitamente com o
  cliente (nenhum cliente fala direto com a BD) que o documento não
  discute com esse detalhe — não parece ser uma decisão deliberada de
  o inverter, mas sim uma formulação genérica ("stored procedures
  como fronteira") escrita sem conhecer a arquitetura já construída.
- **Consequência — trabalho de schema/API ainda por fazer** (ver
  secção 8, não feito nesta entrada porque é uma alteração estrutural
  grande sobre schema já testado):
  - Novas tabelas: **Ordem de Preparação** (agrupa PS) e **Plataforma**
    (gerada pela tipificação) — não existem hoje; `OrdensSeparacao`
    aproxima-se de PS mas falta o nível de agrupamento acima.
  - **Cesto** passa a ter uma instância por (ordem de preparação ×
    plataforma), não só a tabela de referência de tamanhos (`CESTOS`)
    que já existe — precisa de uma tabela nova ou de repensar como
    `CESTOS` é usada.
  - **`TiposPlataforma`** tem hoje P0 como um tipo com dimensões — tem
    de deixar de incluir P0 (que é um fluxo, não uma plataforma) e
    passar a refletir só P4/P2/P1, com as dimensões corrigidas da
    secção 4.7.
  - **`MISSAO`** já suporta um `TipoModulo`/zona genérico, mas o motor
    de criação de missões só existe para picking — falta generalizar
    para packing/transporte/abastecimento/reposição/P0, como o v0.4
    exige.
  - Nomes de tabela exatos para as entidades novas (Ordem de
    Preparação, Plataforma, Cesto-instância) — o cliente deu nomes
    exatos para as tabelas existentes (`TER`/`US`/`ALV`/etc., ADR-011)
    mas não para estas; proponho nomes descritivos até indicação em
    contrário.

### ADR-016 — Motor PS → Ordem de Preparação → Plataforma → Missão implementado (PoC controller/picking)

- **Contexto:** o trabalho de schema da consequência do ADR-015
  (secção 8.1) foi feito, para dar ao `controller` e ao `pda` uma PoC
  próxima do sistema real a implementar, cobrindo a Fase 1 do
  faseamento do v0.4 (tipificação P1, missões de picking).
- **Decisão — schema:** `database/schema.sql` ganhou `Artigos` (dados
  mestre, RF-ENT-03), `OrdensPreparacao`, `Plataformas`, e
  `OrdensSeparacaoLinhas.PlataformaId` (a que plataforma uma linha de
  PS foi destinada). `TiposPlataforma` perdeu `P0` e passou a ter
  `CapacidadeUtilLitros` com os valores corretos da secção 4.7 (P1
  384L, P2 192L, P4 96L). `MISSAO` ganhou `CentroTrabalho`,
  `PlataformaId` e os campos de A.13 (`MotivoPausa`,
  `AtribuidaEm`/`IniciadaEm`/`PausadaEm`/`RetomadaEm`). Tudo por `ALTER
  TABLE` guardado (idempotente), sem quebrar o schema já testado.
- **Decisão — motor de cubicagem/tipificação:** `CubicagemService`
  (`orchestrator/src/Orchestrator.Api/Tipificacao/`) implementa A.1
  (cubicagem de linha), A.2 (volume de ordem), A.4 (escolha de tipo),
  A.5 (decomposição `P1(n)`) e A.8 (índice de camada, com os limiares
  de altura ilustrativos do próprio documento — 140cm/180cm, não
  validados). Os limiares de volume vêm de `TiposPlataforma` (consulta
  à BD), não são constantes de código — cumpre o requisito explícito
  de A.1/A.4.
- **Decisão — circuito completo (ver correção no ADR-017):**
  `POST /api/ordens-preparacao` (receber) → `POST .../tipificar`
  (cubica + tipifica + gera Plataformas, RF-CTL-01/05) →
  `POST /api/plataformas/{id}/despachar` (atribui célula e gera a
  Missão de picking, RF-CTL-06/RF-PIC-01) → `GET
  /api/picking/mission`/`tasks` já não servem uma missão fixa,
  resolvem dinamicamente a mais antiga ainda ativa (ADR-008 "uma de
  cada vez", agora a sério com mais que uma missão possível). O
  `controller` ganhou ecrãs reais: `OrdensPreparacaoPage`
  (tipificar/despachar), `MissoesPage` (agora ligada a
  `/api/missoes`, com pausar/retomar/fechar/reatribuir — A.13 — em vez
  de só leitura).
- **Simplificações desta PoC, deliberadas e documentadas** (não é o
  desenho final):
  1. **Sem Cenário B (plataformas partilhadas P2/P4).** O motor só
     implementa o Cenário A (ordem ≥P1, mono-ordem por plataforma) —
     é exatamente o que a Fase 1 do v0.4 pede. Cenário B
     (partilha por cesto entre ordens pequenas) fica para a Fase 2.
  2. **Distribuição de linhas por plataforma é round-robin**, quando a
     tipificação gera mais que uma plataforma (`P1(n)`). O critério
     real por camada/volume é uma "DECISÃO PENDENTE" do próprio
     documento (A.5/A.8) — não havia informação para fazer melhor.
  3. **Sem tabela de Cesto-instância.** Como só o Cenário A está
     implementado (1 cesto = 1 plataforma sempre), a distinção não
     fazia diferença prática ainda — fica para quando o Cenário B for
     implementado.
  4. **`RegrasMissao` (ADR-010) ainda não entra neste motor** — o
     despacho de plataformas é sempre manual, uma de cada vez, no
     `controller`. (A composição de PS em Ordens de Preparação não é
     manual nem automática no WOPA — ver ADR-017: já chega feita de
     outro software.)
- **Validado, não assumido:** todo o circuito foi testado contra uma
  instância SQL Server 2022 real (Docker), incluindo um bug real
  encontrado e corrigido ao testar (não ao rever código): faltava
  mapear a relação `OrdensSeparacaoLinhas.PlataformaId →
  Plataformas.Id` no `WopaDbContext` — sem isso, o EF Core não sabia
  que precisava de inserir a `Plataforma` nova antes de atualizar a
  linha que aponta para ela, e falhava com violação de FK. Corrigido
  com `HasOne<PlataformaEntity>().WithMany().HasForeignKey(...)`.
  Depois disso, o circuito completo (receber Ordem de Preparação →
  tipificar → despachar → `pda` a picar → missão concluída → próxima
  missão disponível) foi corrido de ponta a ponta com um browser real,
  incluindo pausar/retomar uma missão a meio. **Nota:** esta descrição
  do circuito ficou desatualizada num ponto — "compor" a partir de PS
  já existentes no WOPA deixou de existir, ver ADR-017.

### ADR-017 — Ordens de Preparação chegam já compostas; P0 reinstaurado com dimensões reais

- **Contexto:** o cliente corrigiu duas suposições feitas a partir do
  documento de requisitos v0.4:
  1. As **Ordens de Preparação já chegam compostas** de outro software
     — o agrupamento de PS por cliente/data/morada (RF-CTL-02) não é
     feito no WOPA. O WOPA só tem de **as guardar** para depois tratar
     das etapas seguintes (cubicar, tipificar, despachar).
  2. **P0 existe como tipo de plataforma real**, com dimensões
     conhecidas: palete completa, altura 1,30 m. A **P1** (plataforma
     com 1 cesto, "cesto completo") tem altura real de 0,40 m — o
     v0.4 assumia 0,50 m para todos os tipos de cesto. Isto contraria a
     framing do ADR-015 ("P0 não é um tipo de plataforma") — o cliente
     tem primazia sobre a leitura que fiz do documento.
- **Decisão:**
  1. `POST /api/ordens-preparacao` deixou de compor a partir de PS já
     existentes no WOPA (`psIds`). Passa a **receber a ordem já
     composta**, com os PS incluídos no próprio pedido (cliente, data,
     morada, e a lista de PS com as suas linhas) — grava tudo numa
     transação e devolve o resumo. Não há mais um ecrã de "selecionar
     PS e compor" no `controller` — a **PsPage foi removida**;
     `controller` fica só com **Ordens de Preparação** (recebidas) e
     **Missões**.
  2. A tabela `OrdensSeparacao` (PS) deixou de ter campos próprios de
     cliente/data/morada/canal-de-composição — esses vivem só na
     `OrdensPreparacao` que a contém; `OrdemPreparacaoId` passou a
     `NOT NULL` (um PS nunca existe solto). Removida também a coluna
     vestigial `MissaoId` (nunca foi usada em código nenhum).
  3. `TiposPlataforma` reganha a linha `P0` (palete completa, sem
     cestos) com altura 1,30 m. `P1`/`P2`/`P4` corrigidos para altura
     0,40 m (eram 0,50 m). As capacidades úteis (secção 4.7 do v0.4)
     foram recalculadas com a mesma fórmula do documento (bruto × 0,80
     de margem) para a altura real: **P1 307 L** (era 384),
     **P2 154 L** (era 192), **P4 77 L** (era 96). `P0` fica com
     capacidade útil 0 — não participa na tipificação por volume
     (A.4), continua a ser extraído antes por múltiplos de palete
     completa (A.3, ainda por implementar).
- **Porquê recalcular as capacidades e não só a altura:** a capacidade
  útil de cada cesto (secção 4.7 do v0.4) é derivada da geometria
  (comprimento × largura × altura × margem) — corrigir só a altura e
  deixar a capacidade antiga teria criado uma inconsistência
  silenciosa entre o que a tabela diz e o que a tipificação (A.4)
  calcularia se repetisse a fórmula. Sinalizo este recálculo
  explicitamente para o cliente poder confirmar a aritmética, não é um
  valor que o cliente tenha dado diretamente.
- **Porquê schema limpo em vez de mais `ALTER TABLE`:** a base de
  dados ainda não foi criada em nenhum servidor do cliente — não há
  nada para migrar. `database/schema.sql` foi reescrito com cada
  tabela já no seu formato final (sem os blocos `ALTER TABLE ADD`
  acumulados do ADR-016), reordenado para que as chaves estrangeiras
  se resolvam na própria `CREATE TABLE` sem remendos depois. Validado
  de novo contra uma instância SQL Server 2022 real (Docker, base de
  dados recriada do zero) — script correu limpo, idempotente à
  segunda execução, e o circuito completo (receber Ordem de Preparação
  com PS aninhados → tipificar → despachar) voltou a ser testado com
  sucesso depois da reescrita.

### ADR-018 — Capacidade útil (P1/P2/P4) volta a 384/192/96 L, validada com dados reais; altura física do cesto fica só descritiva

- **Contexto:** o cliente enviou a query real que gera as Ordens de
  Preparação hoje em produção (agrupamento por `bostamp`/`ordem`), com
  os limiares de tipificação **hardcoded em 96000/192000/384000 cm³**
  — exatamente os valores originais do v0.4 (baseados em altura de
  50 cm), não os 77000/154000/307000 que o ADR-017 tinha calculado a
  partir da altura física de 40 cm que o cliente deu para o cesto P1.
  Isto era uma contradição direta a resolver, não a ignorar.
- **Validação com dados reais:** o cliente enviou também
  `estudo_cl_18_meses_anonimizado.xlsx` (as mesmas 18 meses de dados
  do estudo do v0.4 secção 7) — 323.639 linhas de PS, 49.486 PS
  distintos. Recalculei a cubicagem linha a linha (Anexo A.1) e
  comparei a tipificação resultante sob os dois critérios de altura:

  | | Altura 50 cm (query real) | Altura 40 cm (ADR-017) |
  |---|---|---|
  | P4 | 33.877 PS | 31.922 PS |
  | P2 | 4.807 PS | 5.370 PS |
  | P1 | 3.871 PS | 4.057 PS |
  | P1(n) | 6.931 PS | 8.137 PS |
  | **Total de plataformas geradas** | **75.973** | **84.059** (+10,6%) |

  **16,9% dos PS** (8.346 de 49.486) mudam de tipo consoante o
  critério — não é uma diferença marginal.
- **Decisão:** `CapacidadeUtilLitros` em `TiposPlataforma` volta aos
  valores originais **P1 384 L / P2 192 L / P4 96 L**, validados pela
  query real em produção. `AlturaMm` mantém-se em 40 cm para P1/P2/P4
  — **são duas medidas diferentes, não a mesma corrigida duas vezes**:
  a altura física do cesto (40 cm, o que o cliente confirmou) é uma
  coisa; a altura útil de carga para tipificação (50 cm, "limite de
  alcance do operador sobre o cesto" — o operador enche o cesto acima
  do rebordo, dentro do alcance) é outra, e é essa que governa o
  volume de picking. `AlturaMm` fica como campo descritivo (não entra
  no cálculo de `CapacidadeUtilLitros`).
- **Ainda por confirmar com o cliente:** esta reconciliação
  (altura física vs. altura útil de carga) é a minha leitura para
  tornar os dois factos coerentes, não algo que o cliente tenha dito
  explicitamente com essas palavras — sinalizado aqui para
  confirmação, tal como o próprio ADR-017 já tinha pedido.
- **Porquê not manter os dois campos redundantes:** ponderei adicionar
  uma segunda coluna (`AlturaUtilCargaMm`) em vez de reintroduzir o
  valor antigo só em `CapacidadeUtilLitros` — decidi não o fazer nesta
  fase porque a fórmula de capacidade (secção 4.7) já deriva de uma
  única altura; duplicar o conceito antes de ter confirmação do
  cliente arrisca mais confusão do que resolve. `CapacidadeUtilLitros`
  guarda o número validado; `AlturaMm` guarda a dimensão física dada —
  suficiente para a PoC.
- **Descoberta lateral relevante (do mesmo ficheiro):** a folha
  `Rotas` (49.130 linhas: `data_criacao`, `rota`, `PSstamp`) mostra
  como os PS são hoje agrupados na prática — 23.714 rotas distintas,
  57% delas com mais de um PS (até 26 num caso). Das rotas com vários
  PS, 76% são de um único cliente (Cenário A — consistente com ordens
  ≥P1) e 24% misturam clientes diferentes (Cenário B — plataformas
  partilhadas). É a primeira evidência real de como a composição de
  Ordens de Preparação (ADR-017 — feita fora do WOPA) provavelmente
  funciona: por rota de expedição, não só por cliente/data/morada.
  Fica como contexto para quando o Cenário B for implementado
  (secção 8) — não mudei nada com base nisto, só registo.
- **Nota de segurança:** os dados usados nesta validação já vinham
  anonimizados pelo cliente (`cliente` como `CLI####`, `ref` como
  `SKU#####`) — não há códigos reais de artigo nem nomes de cliente
  neste documento.

### ADR-019 — Dados quase-reais carregados na BD; bug de performance (N+1) encontrado e corrigido

- **Contexto:** o cliente pediu para carregar "muita informação" na
  base de dados a partir dos dados reais partilhados (a mesma fonte do
  ADR-018), para o `controller` mostrar um cenário próximo do real, em
  vez dos 3 artigos/1 ordem de exemplo do `schema.sql`.
- **Decisão:** novo ficheiro `database/seed-realistic.sql` (corre
  depois de `schema.sql`, opcional — não faz parte do schema
  "limpo"): catálogo completo de **5.548 Artigos** e **2.500 Ordens de
  Preparação** reais (3.367 PS, 22.362 linhas), todas em estado
  `Aberta` — por tipificar e despachar a partir do `controller`, tal
  como chegariam de verdade. As Ordens de Preparação foram compostas
  usando a evidência real da folha `Rotas` (ver ADR-018): quando uma
  rota tinha um só cliente, os seus PS viram uma Ordem de Preparação
  só; caso contrário, cada PS fica isolado (a composição de rotas
  multi-cliente é o Cenário B, ainda por implementar). A amostra é a
  fatia mais recente dos 18 meses, não os 49.486 PS todos — dimensão
  escolhida para ser "muita informação" sem tornar o ficheiro
  (>3 MB de INSERTs) ou o import impraticáveis.
- **Datas de entrega são estimadas** (data do PS + 3 dias) — não há
  data de entrega real nesta exportação; sinalizado no próprio
  ficheiro para não ser confundido com dado real.
- **Bug real encontrado ao testar com este volume** (não haveria como
  o ver com 1 ordem de exemplo): `GET /api/ordens-preparacao` fazia N+1
  — uma consulta de Artigos e outra de TiposPlataforma **por ordem**,
  em vez de uma vez só. Com 2.500 ordens isto eram ~7.500 round-trips
  à BD e **~15 segundos** de resposta. Corrigido: `CubicagemService`
  ganhou versões síncronas/puras (`CubicarOrdem`, `Tipificar`) que
  recebem os dados já carregados; o endpoint de listagem carrega
  Artigos e TiposPlataforma **uma única vez** e cubica/tipifica todas
  as ordens em memória. Resultado: **~3,6 segundos** — ainda não é
  instantâneo (fica em aberto: paginação/filtro por estado, ver secção
  8), mas já não é uma consulta por ordem.
- **Validado:** `schema.sql` + `seed-realistic.sql` corridos contra
  SQL Server 2022 real (Docker) do zero — sem erros, idempotente à
  segunda execução (~13s a primeira vez, <1s a repetir). A correção de
  performance testada com o volume real carregado, não só com os
  dados de exemplo.

### ADR-020 — Instalação real no IIS do cliente: cinco bloqueios reais resolvidos, um deles fora do WOPA

- **Contexto:** `deploy/install-wopa.ps1` (ADR já implícito no próprio
  script) foi corrido pela primeira vez a sério, no servidor Windows
  do cliente (`WOPASRV`, disco `E:\`), com o utilizador a colar o erro
  exato de cada passo e a correr o comando seguinte que eu indicava.
  Registo aqui os bloqueios encontrados, porque nenhum deles é óbvio a
  reproduzir sem um Windows Server real à frente.
- **Bloqueios encontrados e corrigidos, por ordem:**
  1. Janela do PowerShell a abrir e fechar sem reação nenhuma —
     causa ambígua entre política de execução e falha silenciosa do
     `#Requires -RunAsAdministrator`; removido o `#Requires`, passou a
     haver verificação manual de elevação + `Read-Host` no fim
     (`Wait-BeforeExit`) e todo o corpo do script em `try/catch/finally`.
  2. Comandos corridos em `cmd.exe`, não PowerShell (`Unblock-File`
     "not recognized") — revelou também que a cópia real ficou em
     `E:\wopa\install`, não `C:\wopa\install` como o script assumia;
     `SourceRoot` passou a autodetetar-se via `$PSScriptRoot`.
  3. `Unexpected token 'confirma'` — Windows PowerShell 5.1 a ler um
     ficheiro UTF-8 sem BOM com a codepage do sistema, corrompendo
     acentuação/travessões PT até partir o tokenizer; corrigido a
     acrescentar BOM UTF-8 ao ficheiro.
  4. `File ... is not digitally signed` — política de execução
     `AllSigned`-like no servidor; contornado com
     `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force`
     (só para a sessão, não persistente).
  5. `Este script tem de correr como Administrador` mesmo a janela
     parecendo já elevada — a janela não estava de facto elevada;
     resolvido confirmando o título da janela e usando "Run as
     administrator" a sério.
  - Depois destes cinco, o script correu de ponta a ponta: BD criada e
    populada (5.551 artigos, 2.501 ordens, 3.367 PS, 22.362 linhas),
    `orchestrator` publicado, `pda`/`controller` compilados, os três
    sites do IIS criados — mas o `/health` do `orchestrator` devolvia
    500 genérico.
- **Causa raiz do 500, depois refinado para IIS 500.51 (URL Rewrite):**
  nada disto era do WOPA. O servidor já tinha, de antes, uma regra
  **global** de rewrite em `applicationHost.config`
  (`system.webServer/rewrite/globalRules`, não scoped a nenhum site
  específico):
  ```xml
  <rule name="ReverseProxyTo8080">
      <match url="*" />
      <action type="Rewrite" url="http://192.168.55.2X:8080/{R:1}" />
  </rule>
  ```
  `url="*"` é regex inválida (repeat token sem expressão antes) — isto
  nunca funcionou para o propósito original, e por ser uma regra
  *global* estava a rebentar com **todos** os sites do IIS nesta
  máquina, incluindo `Default Web Site`, não só os três do WOPA.
  Diagnosticado comparando o `web.config` do `orchestrator` (limpo, só
  o handler `aspNetCore`, sem `<rewrite>`) com
  `Get-Website`/pesquisa direta no `applicationHost.config`. Removido
  com `Clear-WebConfiguration -PSPath "MACHINE/WEBROOT/APPHOST" -Filter "system.webServer/rewrite/globalRules/rule[@name='ReverseProxyTo8080']"`
  (com backup do ficheiro antes) — `/health`, `pda` e `controller`
  passaram a responder corretamente nos três sites.
- **Consequência para `install-wopa.ps1`:** o script em si estava
  correto; o bloqueio final era 100% configuração pré-existente do
  servidor, fora do controlo do repositório. Fica registado para o
  próximo deploy (ou próximo servidor) verificar logo à partida se há
  `globalRules` de rewrite não relacionadas com o WOPA antes de
  assumir que um 500 é bug do `orchestrator`.

### ADR-021 — Mais três bugs reais de redeploy corrigidos (BOM, AppPool já parado, mojibake do sqlcmd)

- **`pda`/`controller` a chamar `localhost:5080` em vez do orchestrator
  real:** confirmado via DevTools (`GET http://localhost:5080/api/missoes
  net::ERR_CONNECTION_REFUSED`) — o `.env.production` que o script
  escreve antes do `npm run build` estava a ser escrito com
  `-Encoding UTF8`, que no Windows PowerShell 5.1 grava um BOM; o
  parser de `.env` do Vite não o ignora, a chave passa a
  `﻿VITE_ORCHESTRATOR_URL`, deixa de bater com
  `import.meta.env.VITE_ORCHESTRATOR_URL` no código, e o bundle cai
  silenciosamente no valor por omissão. Corrigido para
  `-Encoding ASCII` (o conteúdo é sempre só um URL `http://host:porta`,
  nunca tem acentuação, por isso é seguro).
- **Redeploy do `orchestrator` falha (`dotnet publish`: ficheiro em
  uso pelo IIS Worker Process):** o hosting model `inprocess` mantém a
  DLL carregada em memória enquanto o AppPool está a correr; num
  redeploy (não na primeira instalação, aí o AppPool ainda não existe)
  isso bloqueia a cópia. Corrigido a parar o AppPool
  `WOPA-Orchestrator` antes do publish e a arrancá-lo depois — mas
  tanto `Stop-WebAppPool` como `Restart-WebAppPool` lançam exceção
  (não suprimida por `-ErrorAction SilentlyContinue`, que aqui não
  chega a apanhar) quando o pool já está no estado que se está a pedir
  ("already stopped" / "have to start stopped object before
  restarting"). Corrigido a confirmar o estado atual do AppPool antes
  de agir, com `try/catch` como rede de segurança.
- **Acentuação corrompida em texto vindo da BD** (`ExpediÃ§Ã£o` em vez
  de `Expedição`, visível no ecrã de seleção de zona do `pda`):
  `sqlcmd`, sem `-f 65001`, lê `schema.sql`/`seed-realistic.sql` (UTF-8
  sem BOM) com a codepage ANSI do sistema — os bytes UTF-8 de "ç"/"ã"
  são lidos como dois caracteres Windows-1252 cada um, e é isso que
  fica gravado na BD. Corrigido a acrescentar `-f 65001` às duas
  chamadas de `sqlcmd`. Como isto **não corrige dados já corrompidos**
  (só o próximo INSERT/UPDATE), as linhas de seed com acentuação
  (`Zonas`, `CM`, `Artigos`/`MissaoLinhas` de exemplo) passaram a ter
  `WHEN MATCHED THEN UPDATE` nos respetivos `MERGE` — antes só tinham
  `WHEN NOT MATCHED THEN INSERT`, pelo que nunca corrigiam uma linha já
  existente por muitas vezes que o script corresse. Basta correr
  `schema.sql` outra vez (sem `-SkipDatabase`) para autocorrigir os
  dados já em produção.

### ADR-022 — Picking passa a exigir alvéolo + quantidade escolhidos pelo operador (não só o scan)

- **Contexto:** o `pda` original só pedia o scan do código de barras,
  incrementando a quantidade lida em 1 por leitura, sem o operador
  indicar de onde estava a separar. O cliente corrigiu: "além de picar
  o código de barras tenho que dizer obrigatoriamente qual o alvéolo
  onde estou (lista de stock daquela ref, naquela zona onde estou) e
  indicar a quantidade que vou separar, sugerindo caso haja stock
  daquela ref, naquele alvéolo, a totalidade da necessidade da missão,
  podendo o operador ter necessidade de alterar."
- **Decisão:** o scan deixa de alterar `QuantidadeLida` — passa a ser
  só o gate que confirma "artigo certo" e desbloqueia o passo
  seguinte. Novo passo obrigatório depois de cada scan válido: lista
  de alvéolos com stock do artigo **na zona onde o operador está**
  (não um alvéolo fixo à partida), com quantidade sugerida = falta da
  missão, limitada ao que esse alvéolo tem disponível — editável.
  Confirmar um pick decrementa `SA`, regista o movimento em `SL`
  (`CM=501`, "Saída por picking") e soma à quantidade lida da tarefa;
  se ainda faltar quantidade, volta ao scan (pode vir de outro
  alvéolo); se completa, fecha a tarefa como antes (`/confirm`
  inalterado).
- **Reaproveita o modelo já desenhado, não cria tabela nova:** `SA`
  (stock atual por artigo+alvéolo) e `SL` (ledger de movimentos) já
  existiam no `schema.sql` desde a normalização do schema mas nunca
  tinham sido mapeadas no EF Core nem tinham dado nenhum — ganharam
  `EstoqueAlveoloEntity`/`MovimentoStockEntity` e dois endpoints novos
  (`GET /api/picking/tasks/{id}/alveolos`,
  `POST /api/picking/tasks/{id}/pick`, ambos idempotentes via
  `OperacoesProcessadas`, como `/scan`/`/confirm`).
- **Stock de demonstração:** `schema.sql` ganhou `SA` para os 3
  alvéolos de exemplo já existentes — de propósito com o SKU-1001 em
  **dois** alvéolos da mesma zona, para o ecrã mostrar mesmo uma
  escolha real. Ao contrário dos `MERGE` de dados de referência
  (Zonas/CM/Artigos), isto usa `IF NOT EXISTS` sem `UPDATE`: é dado
  "vivo" que o próprio picking decrementa, por isso reaplicar
  `schema.sql` não pode repor os valores iniciais por cima do que já
  foi picado. **Sem stock real carregado para os 5.548 artigos do
  `seed-realistic.sql`** — só os 3 alvéolos de exemplo têm `SA`; fica
  em aberto (ver secção 8) de onde vem esse número para o armazém
  real, decisão do cliente: "o WOPA calcula sozinho a partir dos
  movimentos" — ou seja, `SA`/`SL` continuam a ser a fonte de
  verdade, só falta um import inicial de stock atual para arrancar
  quando o layout real do armazém chegar.
- **Offline (ADR-007):** o pick em si fica na fila de saída como
  scan/confirm, mas a lista de alvéolos-com-stock é sempre pedida em
  direto (não há cache local) — se o dispositivo estiver offline nesse
  momento, mostra erro com "tentar novamente" em vez de deixar
  escolher um alvéolo com dados potencialmente errados. Fica em
  aberto se vale a pena cachear isto como as tarefas já são.
- **UX — foco/avanço automático entre campos:** pedido explícito do
  cliente, aplicado já neste fluxo novo: escolher o alvéolo avança o
  foco sozinho para o campo de quantidade (com o valor sugerido
  pré-selecionado, pronto a ser substituído com um único toque) — sem
  o operador ter de tocar no campo. Mantém o princípio já usado no
  scan (o input do código de barras mantém-se sempre focado, ADR
  original do módulo picking).

### ADR-023 — Instalar o pda em Android via wrapper Capacitor (não TWA), sem HTTPS

- **Contexto:** o cliente pediu instalação em Android como app (APK),
  com atualização automática depois de instalada uma vez. O caminho
  padrão para uma PWA (já é uma, ADR-002, com service worker via
  vite-plugin-pwa) seria um **TWA** (Trusted Web Activity) — mas isso
  exige HTTPS com certificado confiável (verificação por Digital Asset
  Links). Confirmado com o cliente: "vai ser sempre IP ou hostname
  interno... é uma app para rede interna e uso interno dentro da
  empresa" — sem domínio público, sem CA confiável ao alcance sem
  atrito operacional considerável (montar CA interna + instalar em
  cada telemóvel).
- **Decisão:** wrapper **Capacitor** em vez de TWA — um `WebView`
  Android fino, sem código nenhum do `pda` embrulhado, sempre a
  apontar para o URL real do servidor (`pda/capacitor.config.ts`).
  Cleartext (HTTP) autorizado só para esse host específico via
  `network_security_config.xml` — nada mais no dispositivo fica
  autorizado a HTTP. Dá exatamente a mesma propriedade que o TWA
  daria: instala-se uma vez, cada arranque carrega a versão mais
  recente publicada no IIS, sem mecanismo de atualização nenhum a
  gerir (não há nada para atualizar no telefone — é sempre a mesma
  página web a carregar).
- **Scaffold feito, compilação por fazer:** `npx cap add android`
  gerou `pda/android/` (projeto Gradle completo, versionado — exceto
  `build/`, `.gradle/`, `local.properties` e chaves de assinatura,
  nunca commitados). Este sandbox não tem acesso à rede do Android SDK
  (`dl.google.com` bloqueado pelo proxy de saída) — só Java/Gradle,
  sem SDK — por isso não foi possível compilar um `.apk` real aqui.
  Guia completo em `pda/android/BUILD.md` para compilar numa máquina
  com Android Studio.
- **Cabeçalho do pda:** ligação "Instalar em Android" persistente em
  todos os ecrãs (`RootLayout.tsx`, ao lado do indicador de ligação já
  existente do ADR-009), a apontar para `/wopa-pda.apk` — ficheiro
  estático que fica em `pda/public/` depois de compilado (ver
  BUILD.md), servido pelo próprio `pda`. Escondida sozinha quando a
  app já está a correr dentro do wrapper instalado
  (`window.Capacitor?.isNativePlatform?.()`), para não mostrar
  "instalar" a quem já instalou.
- **Risco documentado:** o host do servidor fica fixo dentro do APK
  (`capacitor.config.ts` + `network_security_config.xml`, os dois têm
  de bater certo) — ao contrário do resto da app, que atualiza sozinha
  a cada arranque, mudar o IP/hostname do servidor implica recompilar
  e reinstalar o APK em todos os dispositivos.

### ADR-024 — Modernização visual do pda e do controller (cores/fontes mantidas)

- **Contexto:** o cliente não gostou do layout anterior ("sem cantos
  arredondados", listas planas com divisórias, tags de contorno fino)
  e pediu para modernizar, mantendo a paleta e tipografia atuais,
  inspirado (não copiado) em screenshots de outra aplicação sua (WIN
  Suporte) — cartões arredondados com sombra, pills de estado com
  fundo colorido, filtros em separadores (segmented control), cartões
  de estatística.
- **Decisão:** mantidos os tokens de cor/fonte dos dois `index.css`
  (creme `#faf8f4`, texto quase-preto, dourado `#b9962e`, serif
  Georgia nos títulos) — só a linguagem visual dos componentes mudou:
  cantos arredondados (`--radius-sm/md/pill`) e sombra suave
  (`--shadow-card`) em cartões/painéis/tabelas/botões/inputs; estados
  (`status-tag`/`task-card__status`) passam a pill com fundo colorido
  suave em vez de texto/contorno; `pda`: `TaskList` ganha um filtro em
  separadores "Tudo/Por fazer" com contagem (padrão mais visível dos
  screenshots de referência); `controller`: barra lateral com item
  ativo em pill dourada preenchida em vez de contorno lateral.
- **Cartões de estatística — só com dados reais:** `MissoesPage` e
  `OrdensPreparacaoPage` ganharam um `stat-grid` no topo (em execução/
  por atribuir/pausadas/concluídas hoje; abertas/tipificadas/
  despachadas/total) — todos calculados em memória a partir da lista
  já carregada da API, nunca inventados nem vindos de um endpoint novo.
- **Sem contexto de utilizador na barra do `controller`:** os
  screenshots de referência mostram uma barra "empresa · utilizador ·
  função" — não replicado, porque o `controller` ainda não tem sessão/
  login (ADR-013, "em falta em quase todo o lado", secção 8); mostrar
  isso agora seria inventar dados que não existem. Fica para quando o
  login do `controller` for feito.

### ADR-025 — Bug real corrigido: pill de estado cortada no pda; Tipificar/altura explicados no ecrã

- **Bug de layout (visto ao vivo no telemóvel do cliente):** a pill de
  estado ("PENDENTE") no `TaskList` do `pda` aparecia cortada/sem
  texto visível. Causa: `grid-template-columns: auto 1fr auto` — sem
  `min-width: 0` na coluna da descrição (1fr), essa coluna recusa-se a
  encolher abaixo do seu conteúdo mínimo e espreme a coluna da pill.
  Corrigido: `minmax(0, 1fr)` na descrição e `minmax(78px, auto)`
  garantido para a coluna de estado, mais `white-space: nowrap` na
  própria pill. Mesma proteção aplicada preventivamente a
  `.option-card__tag` (mesmo padrão de pill, ainda sem o bug
  manifestado).
- **"Não entendo o Tipificar/altura da palete final":** confirmado com
  o cliente que a lógica fica como está (Anexo A.4/A.5/A.8) — só
  faltava explicar no próprio ecrã. `OrdensPreparacaoPage` ganhou um
  parágrafo antes do botão a dizer o que `Tipificar` calcula e produz,
  e um aviso depois do campo de altura a dizer que só importa quando a
  ordem gera mais que uma plataforma, e que a regra do limiar (140 cm)
  é provisória — ver ADR-016/017, "DECISÃO PENDENTE" do próprio
  documento v0.4, secção 8.

### ADR-026 — Tipografia modernizada: Inter + Fraunces, auto-hospedadas

- **Contexto:** pedido do cliente para modernizar a fonte, com
  pesquisa do que está em uso em SaaS/dashboards atuais.
- **Decisão:** `Inter` no texto/UI (o sans-serif mais instalado da
  web em 2026, desenhado para ecrã, base de facto de dashboards/SaaS)
  e `Fraunces` nos títulos (serifada com mais carácter que o Georgia
  anterior, mantém o tom editorial da marca — combinação "sans para
  UI + serif de destaque nos títulos" é o padrão mais recomendado
  atualmente). Cores mantidas.
- **Auto-hospedadas, não CDN da Google Fonts:** o `pda`/`controller`
  correm numa rede interna da empresa sem internet garantida
  (ADR-023) — um CDN externo faria a fonte falhar ou atrasar o
  primeiro carregamento fora dessa rede. Ficheiros `.woff2` variáveis
  (um por família cobre todos os pesos usados) em `public/fonts/` de
  cada projeto, só o subset "latin" (cobre toda a acentuação PT-PT,
  dentro de U+00FF) — não os subsets cirílico/grego/vietnamita que a
  Google serve por omissão. `<link rel="preload">` no `index.html`
  de cada app para evitar flash de texto sem estilo.
- **Barra de topo do pda sobreposta à área de sistema do telemóvel**
  (visto ao vivo): `viewport-fit=cover` adicionado ao `index.html` do
  `pda` + `env(safe-area-inset-top/bottom)` no `.root-layout__bar` e no
  `.app`, para o conteúdo respeitar sempre a barra de estado/gestos do
  telemóvel em vez de ficar por baixo dela.
- **Suspeita (por confirmar):** o cliente reporta as fontes iguais às
  antigas mesmo depois do deploy — provável causa: IIS sem o tipo MIME
  `.woff2` registado (comum em versões mais antigas do Windows Server),
  fazendo o `@font-face` falhar silenciosamente e cair no Georgia do
  `font-family` fallback. Por confirmar via DevTools (Network, código
  de estado do pedido a `inter-variable.woff2`) antes de mexer no
  `web.config` — arriscado adicionar um `mimeMap` duplicado sem saber
  se já existe ao nível do servidor.

### ADR-027 — Reunião de planeamento: capacidade/despacho com data no controller, motivos de exceção no pda

- **Contexto:** o cliente gravou uma reunião interna sobre o desenho do
  `controller` e do `pda`-Picking e pediu para enquadrar contra tudo o
  que já existia, esclarecer o que ficou por fechar, e só avançar
  depois de decisões explícitas — ver a transcrição completa na
  conversa. Quatro decisões saíram dessa troca:
  1. **Identificador de "caixa" = EAN do artigo**, não um ID único por
     caixa. Já era o desenho existente (`MissaoLinha.CodigoBarras`) —
     zero mudança de schema. Fica documentado que uma etiqueta única
     por caixa é um passo maior, só a fazer se dados reais mostrarem
     necessidade.
  2. **`controller` e `pda` avançam com a mesma prioridade** — ambos
     endereçados nesta ADR.
  3. **Missão pode nascer "Planeada"** (não só quando o dia chega) —
     novo estado antes de "Criada" (A.13 estende-se).
  4. **`packing` (double-check/consolidação obrigatório) fica de fora
     por agora** — não criado nenhum scaffold, só desenhado aqui como
     dependência futura.
- **Controller — capacidade e despacho com data:**
  - Nova tabela `Celulas` (capacidade diária **constante**, não um
    calendário completo — "a capacidade inicial pode ser estimada e
    afinada com histórico ao fim de 3-6 meses", tal como discutido).
    Seed com 2 células de exemplo (500 unidades/dia cada).
  - `POST /api/plataformas/{id}/despachar` ganha `celulaId` e
    `dataDespacho` opcionais. Data futura → Missão nasce com
    `Estado="Planeada"` e `DataPlaneada` preenchida, em vez do
    `"Criada"` imediato de sempre. Sem transição de estado explícita
    quando o dia chega — `ObterOuAtribuirMissaoAtualAsync` (o pda a
    pedir trabalho) já trata "Planeada com `DataPlaneada` ≤ hoje" como
    equivalente a "Criada", poupando um job/cron só para isto.
  - Novo `GET /api/celulas/carga?data=`: carga vs. capacidade por
    célula nesse dia — "unidades" é a soma de `QuantidadeAlvo` das
    linhas das missões atribuídas à célula (métrica simples e
    **deliberadamente provisória**, por afinar com histórico real —
    o próprio cliente reconheceu nesta reunião que os primeiros meses
    vão ter previsões erradas).
  - Nova página `controller` "Capacidade": grelha por célula, um dia
    de cada vez (seletor de data), carga/capacidade/%, marca "saturada"
    a partir de 100%.
  - `OrdensPreparacao` ganha `Urgente` (bool) + `DataLimite` — marcado
    pelo supervisor no `controller` (`POST .../urgente`), nunca vem da
    origem. Lista de Ordens de Preparação ordena urgentes primeiro —
    fila com prioridade, mas **sem** arrastar-para-reordenar ainda
    (fica em aberto, ver abaixo).
- **PDA — motivos de exceção e confirmação rápida:**
  - `SL` (ledger de movimentos, ADR-022) ganha `Motivo` — obrigatório
    no ecrã (`PickAlveolo`) só quando a quantidade picada difere da
    sugerida ("Falta de stock" / "Caixa incompleta" / "Dano" / "Outro")
    — é exatamente o travão contra "pico 10 e levo 9" que saiu da
    reunião, sem obrigar a digitar sempre.
  - Novo botão "Confirmar N" de um só toque quando a quantidade
    escolhida bate certo com a sugestão — não precisa de tocar no
    teclado nem escolher motivo nenhum. Só aparece o campo de motivo
    quando o operador já mudou o número.
- **Migração real, não só CREATE TABLE:** como já existe uma BD em
  produção sem estas colunas, `schema.sql` teve pela primeira vez de
  usar `ALTER TABLE` guardado por existência de coluna (secção 22),
  não só o padrão `CREATE TABLE IF NOT EXISTS` do resto do ficheiro
  (ADR-017) — continua idempotente, mas é a primeira vez que este
  ficheiro precisa mesmo de "migrar" algo já implantado.
- **Deliberadamente fora de alcance desta ADR** (ver Em aberto): matriz
  de validação por tipo de plataforma (palete inteira/caixa fechada/
  fracionado/vertical — hoje o fluxo do ADR-022 trata tudo da mesma
  forma), put-to/transferência para zona de destino, integração
  vertical, arrastar-para-reordenar a fila de urgências, capacidade por
  zona (só célula por agora), modelo de KPIs (produtividade/qualidade/
  serviço), e o próprio `packing`.

### ADR-028 — Segunda pass visual, mais ousada (pda feito; controller por fazer)

- **Contexto:** a modernização do ADR-024 não foi longe o suficiente para
  o cliente ("já te vi fazer coisas mais bonitas... sê criativo e
  moderno") — sem referência concreta para seguir, decisão de ir mais
  longe por iniciativa própria, mantendo a paleta e as fontes já
  escolhidas (ADR-026).
- **`pda` (feito):** textura de grão subtil no fundo (ruído SVG inline,
  opacidade ~3.5%, efeito "papel" em vez de cor totalmente lisa);
  tipografia mais expressiva nos títulos e no número grande de
  progresso, usando os eixos da própria fonte variável Fraunces
  (`font-variation-settings: "opsz"`, tamanhos maiores, menos peso
  "neutro"); entrada em cascata animada nas listas (`TaskList`,
  `option-list`) — cada cartão aparece um pouco depois do anterior,
  até ao 10º item.
- **`controller`:** ainda por fazer — próximo passo.

### ADR-029 — Gate de montagem no picking: não há picking de artigos sem plataforma indicada

- **Contexto:** notas do cliente vindas do armazém a sério — uma
  plataforma é montada (palete + cestos) antes do picking de artigos, e
  não depois. Um operador na Zona A pode receber uma missão cuja
  plataforma já vem "agarrada" de uma zona anterior (a mesma Ordem foi
  tocada por vários zonas/missões em sequência) — nesse caso só confirma
  a plataforma; só a **primeira** zona a tocar numa Ordem é que monta de
  raiz.
- **Regra implementada:** `POST /api/picking/mission/{id}/montagem`
  (`matriculaPalete`, `matriculasCestos[]`). Se a `Plataforma.MontadaEm`
  ainda é nula, é a primeira zona — a matrícula da palete e as N
  matrículas de cesto (N = `TiposPlataforma.CestosPorPlataforma`, 0 para
  P0) ficam gravadas (`Plataformas.MatriculaPalete`/`MontadaEm`, tabela
  nova `PlataformaCestos`). Se já está montada, é confirmação leve: só
  valida que a palete e os cestos lidos correspondem aos já gravados,
  sem os poder trocar por aqui. Nos dois casos, o resultado marca
  `MISSAO.PlataformaConfirmada = true` — **por missão**, não por
  plataforma, porque cada zona/missão precisa da sua própria confirmação
  mesmo que a plataforma já esteja montada. `GET /api/picking/tasks/{id}
  /scan` e `/pick` recusam (409) enquanto isto não estiver feito;
  `GET /api/picking/mission` já devolve o que falta (`montagem`, com
  `primeiraMontagem` a distinguir os dois ecrãs no `pda`).
- **P0 tratado como o resto:** `TiposPlataforma` já tinha uma linha P0
  com `CestosPorPlataforma = 0` — a mesma regra serve sem caso especial:
  só pede a matrícula da palete, nenhum cesto. Isto está em tensão com o
  texto do ADR-017 ("P0 ... fora do circuito de corredores, executado
  pelo empilhador de abastecimento") — as notas mais recentes do cliente
  descrevem P0 a passar pelo mesmo gate de picking, "já no alvéolo para
  picking". Resolvido aqui do lado seguro (P0 só pede palete, nunca
  bloqueia por cestos que não existem), mas fica por confirmar com o
  cliente se isto é mesmo o fluxo real do P0 ou uma mistura de dois
  conceitos — ver Em aberto.
- **Cesto ainda não é uma tabela de instâncias com matrícula própria**
  (`CESTOS` continua só tipo/spec, uma linha "cesto-standard") — a
  matrícula de cesto lida no gate fica como texto solto em
  `PlataformaCestos.MatriculaCesto`, sem FK para nenhuma tabela de
  cestos físicos. Suficiente para validar "é a mesma plataforma" entre
  zonas, mas não persegue o cesto como património reutilizável — isso
  cruza com a sugestão de melhorias ao `ALV` (ver mensagem em separado).
- **`pda`:** ecrã novo `MontarPlataforma` antes de qualquer leitura de
  artigo — pede a matrícula da palete e, se o tipo tiver cestos, lê-as
  uma a uma com contador N/M. Sempre em direto (como a lista de
  alvéolos com stock do ADR-022) — a validação de "é a mesma plataforma"
  só o servidor pode fazer, por isso não entra na fila offline do
  ADR-007.
- **`controller`:** tabela de Missões mostra "Por montar" junto da
  plataforma quando há gate por cumprir, para o supervisor ver de
  imediato onde está parada uma missão.
- **Deliberadamente fora de alcance:** `packing` (o próprio cliente
  pediu para ficar só na ideia por agora — não há libertação de
  plataforma/cestos implementada); qualquer scan por artigo do cesto de
  destino durante o picking ("não posso misturar encomendas no mesmo
  cesto") — isso é uma segunda regra, sobre `MissaoLinhas.CestoId`/
  `CestosNecessarios` (colunas que já existem no schema, por popular),
  não sobre este gate de entrada.

### ADR-030 — `ALV` com tipo e posição estruturada; cesto passa a ter matrícula própria (`CestoInstancias`)

- **Contexto:** resposta às sugestões de melhoria ao `ALV` levantadas em
  ADR-029 — o cliente escolheu duas das três (tipo de alvéolo e posição
  estruturada, não capacidade) e pediu para avançar também com a tabela
  de instância de cesto que tinha ficado só na ideia.
- **`ALV` ganha `Tipo`** (`Picking | Reserva | Deposito | Buffer`,
  default `Picking`) — agora dá para marcar o "depósito" de paletes/
  cestos vazios (para onde uma plataforma volta ao ser libertada, ver
  ADR-029) e um eventual buffer de packing como alvéolos normais, só que
  de outro tipo, em vez de precisarem de tabela própria.
- **`ALV` ganha `Corredor`/`Coluna`/`Nivel`** (estruturado, não só o
  `Codigo` em texto) — base para a sequenciação de rota dentro do
  corredor que já estava listada como decisão em aberto do v0.4 (A.9).
  Os 3 alvéolos de exemplo foram retro-preenchidos a partir do próprio
  `Codigo` (`"A-01-03"` → corredor `A`, coluna 1, nível 3).
- **`CestoInstancias` (tabela nova):** `Id, Matricula (única), TipoCestoId
  (FK a CESTOS, que continua só o tipo/spec), Estado (Livre|EmUso),
  LocalizacaoAtualId (FK a ALV, NULL enquanto EmUso — em circulação, sem
  alvéolo fixo)` — o mesmo desenho já proposto para a Plataforma
  (`LocalizacaoAtualId → Alveolos`) no artigo da base de dados.
- **Wiring com o gate de montagem (ADR-029):** `PlataformaCestos`
  mantém-se como estava (é o que valida "é a mesma plataforma" entre
  zonas) — mas agora, sempre que o gate lê uma matrícula de cesto, o
  próprio endpoint garante que existe uma `CestoInstancia`: se a
  matrícula já é conhecida, só muda de estado para `EmUso`; se é nova,
  cria a instância ali mesmo. Ainda não há um ecrã/fluxo de pré-registo
  de equipamento — a primeira vez que um cesto físico é lido é que ele
  "nasce" no sistema.
- **Simplificação assumida:** como só há um tipo de cesto seedado
  (`cesto-standard`), a instância nova usa sempre esse tipo por omissão
  — por revisitar quando existir mais do que um tipo de cesto real.
- **Fora de alcance:** a transição para `Livre`/volta ao depósito
  (`LocalizacaoAtualId` preenchido) depende do `packing`, que continua
  deliberadamente por fazer.

- **Da reunião de planeamento (ADR-027), por implementar quando houver
  mais clareza:** matriz de validação no `pda` por tipo de plataforma
  (P0/caixa fechada/fracionado/vertical); put-to/transferência para
  zona de destino (frigorífico/consolidação/buffer) com scan próprio;
  integração com o vertical (que eventos/confirmações ele expõe);
  arrastar-para-reordenar a fila de urgências no `controller`, com
  impacto visível ("se meteres isto hoje, o que escorrega para
  amanhã?"); capacidade por zona/corredor (só célula está feito);
  modelo de KPIs (produtividade + qualidade + serviço, não só
  velocidade); `packing` (double-check/consolidação obrigatório) —
  scaffold nenhum ainda, por pedido explícito do cliente.
- **P0 no gate de montagem (ADR-029): confirmar com o cliente.** Fica em
  tensão com o ADR-017 ("P0 fora do circuito de corredores"). Por
  confirmar se P0 passa mesmo pelo `pda`/gate de montagem tal como
  descrito nas notas mais recentes, ou se essas notas descreviam outro
  ponto do fluxo (empilhador/reserva) sendo o nome "P0" usado de forma
  solta.
- **Capacidade do `ALV` (sugestão do ADR-029 não escolhida por agora):**
  nenhum limite volumétrico/unidades associado ao alvéolo — nada impede
  sugerir um alvéolo já cheio, nem o `controller` sabe quando um
  "depósito" está sem espaço para equipamento livre. Fica para quando
  fizer falta a sério.
- **Origem do stock real por alvéolo (ADR-022):** `SA`/`SL` calculam-se
  sozinhos a partir dos movimentos (decisão do cliente), mas falta o
  import inicial — hoje só os 3 alvéolos de exemplo têm `SA`, nada
  para os 5.548 artigos do `seed-realistic.sql`. Por fazer quando o
  layout real do armazém chegar (ver ponto seguinte).
- **Paginação/filtro em `GET /api/ordens-preparacao`** (ADR-019): já
  não faz N+1, mas devolve sempre todas as ordens (2.500+ na PoC com
  dados reais, ~3,6s). Filtrar por defeito às não despachadas, ou
  paginar, antes de o volume real do cliente (49 mil PS em 18 meses)
  tornar isto lento outra vez.
- **Mais contexto do armazém a caminho** (o cliente vai enviar) — a
  planta física, zonas adicionais além de OUTLET/ARMAZÉM
  AUTOMÁTICO/ARMAZÉM (ALVÉOLOS), e as regras de negócio completas.
- Motor de ordenação de missões por prioridade de zona (secção 4.6) —
  configurável, não hardcoded; entronca nas `RegrasMissao` (ADR-010).
- Comportamento das linhas do `ARMAZEM AUTOMATICO` no `pda` — chegam a
  um operador humano ou são geridas por um sistema automático à parte?
- **`controller` — ecrã de missões, próximo passo:** já tem
  pausar/retomar/fechar/reatribuir (A.13, ADR-016) — falta a visão de
  "front office" mais rica que o cliente pediu (ocupação de buffers,
  plataformas em circulação, alertas de envelhecimento — RF-CTL-10) e
  a navegação hierárquica entre PS/Ordem/Plataforma/Missão (RF-CTL-11).
- **Login user+PIN em falta em quase todo o lado (ADR-013):** o `pda`
  pede só o número (sem PIN, sem validar contra `US`); `controller`,
  `core-config` e `packing` não têm ecrã de login nenhum ainda.
  Autenticação/autorização entre clientes e o `orchestrator` também
  por desenhar (ex.: JWT emitido pelo `orchestrator`, um por
  dispositivo/utilizador). `US.Pin` está em texto simples na PoC —
  tem de passar a hash antes de produção.
- `packing` ainda não tem projeto (scaffold por fazer) — decisão de
  stack já tomada (PWA React/TS/Vite, ADR-006); falta arrancar, e
  decidir se precisa de funcionar offline como o `pda` (ADR-007).
- **Connection string real do cliente para o SQL Server de produção**
  (ADR-012) — o `orchestrator` já lê/escreve em SQL Server a sério,
  mas só foi testado contra um contentor Docker local desta sandbox.
  Preciso da connection string real (ou de acesso a uma instância de
  teste do cliente) para validar contra o servidor verdadeiro.
- **`SL`/`MovimentosStock` e `SA`/`StockArmazem`** — as tabelas existem
  no schema (ADR-011) mas nada ainda lá escreve. Falta decidir quando
  um `scan`/`confirm` de picking deve gerar um movimento de stock
  (`CM_ID` de saída) e atualizar o stock por alvéolo.
- Módulos `transporte` e `abastecimento`: desenhar o que cada um move
  e que "missão" faz sentido para cada um — e aplicar-lhes o mesmo
  padrão offline-first do ADR-007.
- Ecrã de resolução de conflitos de sincronização (ver limitações do
  ADR-007) — só vale a pena desenhar se se mostrar necessário na
  prática.
- Limite de armazenamento local do IndexedDB e política de limpeza de
  missões antigas já sincronizadas no dispositivo.
- **PHC vs. OrdersHub** (ADR-008/011/017): já não é "quem se consulta"
  — passou a "quem chama" `POST /api/ordens-preparacao`, já com a
  ordem composta. Falta confirmar se é o PHC, o OrdersHub, ou os dois,
  e se é uma integração direta ou passa por um conector/middleware
  intermédio.
- **Despacho ainda um a um, sem `RegrasMissao` (ADR-016/017):** o
  `controller` já tipifica e despacha a sério Ordens de Preparação
  recebidas — mas cada tipificação/despacho é feito manualmente, uma
  ordem/plataforma de cada vez, e o motor não usa `RegrasMissao`
  (ADR-010) para nada ainda (sem lote, sem critério automático).
- **"Próxima missão": critério de atribuição.** `GET
  /api/picking/mission`/`tasks` já resolvem dinamicamente a missão
  mais antiga ainda ativa (ADR-016) em vez de uma fixa — mas sempre a
  mesma para qualquer PDA que pergunte. Falta um critério por
  operador/zona/dispositivo quando houver mais que um PDA a picar ao
  mesmo tempo (fila simples? prioridade? por zona do operador?).
- **Cenário B (plataformas partilhadas P4/P2) não implementado**
  (ADR-016) — só o Cenário A (ordem ≥P1, mono-ordem) tem motor. Fica
  para a Fase 2 do faseamento do v0.4 (secção 4.7), junto com a
  composição de cestos por afinidade (A.7, "DECISÃO PENDENTE" do
  próprio documento) e a distribuição de linhas por camada em vez de
  round-robin (ver ADR-016, simplificação 2).
- **Dados mestre de artigo (`Artigos`) só têm o seed de exemplo** —
  falta o endpoint/processo real de integração com o ERP para os
  manter atualizados (RF-ENT-03/04); `POST /api/artigos` já existe e
  aceita upsert em lote, só falta quem o chame a sério.

### 8.1 Rework de schema/API do v0.4 — feito (ADR-016), com simplificações conhecidas

O trabalho estrutural planeado nesta secção **foi feito** — ver
ADR-016 para o detalhe do que foi implementado e testado. O que ficou
deliberadamente simplificado (Cenário B, distribuição por camada, Cesto
como instância) está listado nos itens novos acima, não repetido aqui.
Ainda por resolver:

- **Nomes de tabela exatos para as entidades novas** (`OrdensPreparacao`,
  `Plataformas`, e a futura tabela de Cesto-instância quando o Cenário
  B for construído) — o cliente só deu nomes fixos para as tabelas já
  existentes (ADR-011); usei nomes descritivos (ADR-015), a corrigir se
  o cliente pedir códigos específicos.
- **Generalizar `MISSAO` para os outros 5 centros de trabalho**
  (packing, transporte, abastecimento, reposição, P0) — a coluna
  `CentroTrabalho` já existe no schema, mas só o motor de picking gera
  missões; os outros centros ainda não têm lógica nenhuma.

### 8.2 Decisões que o próprio documento v0.4 deixa em aberto

Não preciso de as levantar ao cliente agora — o documento já as
assinala como pendentes ("DECISÃO PENDENTE", Anexo A / secção 8);
registo aqui só para não se perderem quando chegar a essa parte da
implementação:

- Padrão de empilhamento quando os SKUs disponíveis não têm a
  proporção pesado/leve certa para o ciclo (A.8), e a tabela que
  mapeia altura da palete → valor de N (só há valores ilustrativos:
  N=2 até 140 cm, N=3 até 180 cm, não validados).
- Cálculo de `n_plataformas` por volume (A.5) vs. por número de
  camadas de empilhamento (A.8) — podem divergir; falta decidir se é o
  máximo dos dois.
- Regra de atribuição de frentes de picking: 5.500 referências para
  2.856 frentes disponíveis — quais têm frente fixa, quais rodam,
  quais servidas da reserva (A.10 / secção 8 do v0.4).
- Critério de afinidade para propor agrupamento automático de
  plataformas partilhadas (A.7): proximidade de corredores, destino de
  expedição, ou ordem de chegada.
- Âmbito da partilha de cestos: mono-cliente estrito vs. partilha por
  dia/célula (~31% menos viagens na análise) — recomendado
  parametrizável.
- Limite de tolerância offline: quanto tempo um PDA pode trabalhar sem
  rede antes de se bloquear, para não haver trabalho sobre missões já
  reatribuídas (A.13) — relevante diretamente para o ADR-007/009 já
  implementados no `pda`.
- Se uma ordem parcialmente satisfeita aguarda o remanescente (onde? —
  buffer da célula, zona de espera dedicada) ou é sempre expedida
  parcialmente (A.14).
- Plataforma órfã (picking já iniciado numa ordem que muda) — fora de
  âmbito da v1, mas o v0.4 já descreve o conceito para produção
  (secção 8/RF-CTL-08).
- Sequenciamento dentro do corredor (A.9): admite mais de uma passagem
  quando reduz subidas? O retorno ao ponto de saída conta como
  passagem útil?
- Periodicidade de recálculo do slotting vertical e quem o executa
  (A.10) — implica movimentação física de stock.
- Tempos operacionais reais (pick por nível, transporte, packing por
  modo, abastecimento de topo, taxa de falta) — "a variável mais
  determinante de todo o dimensionamento", ainda por medir (não há
  man-up instalado para cronometrar).
