/*
    WOPA — script de criação da base de dados (Microsoft SQL Server)
    ================================================================

    Cria a base de dados "WOPA" com todas as tabelas num único schema
    (dbo) — decisão do cliente: mais simples de gerir na prática do que
    separar por módulo, sobretudo havendo tabelas partilhadas entre
    aplicações (ver ADR-003).

    Modelo de domínio alinhado com o documento de requisitos v0.4 e com
    as correções diretas do cliente (ADR-015/016/017): a "Ordem de
    Preparação" (OrdensPreparacao) chega já composta de outro software
    — o WOPA só a recebe e guarda (POST /api/ordens-preparacao) — a
    partir daí é que trata da tipificação (gera Plataformas) e do
    despacho (gera Missões).

    Como correr:
      sqlcmd -S <servidor> -E -i schema.sql
    ou abrir no SQL Server Management Studio / Azure Data Studio e
    executar (F5).

    Script limpo, não uma migração: como a base de dados ainda não
    existe em nenhum servidor do cliente, cada tabela é criada já com
    o seu conjunto final de colunas — sem blocos ALTER TABLE a
    remendar um schema anterior. Ainda assim seguro para voltar a
    correr (cada CREATE está guardado por um IF NOT EXISTS e o seed usa
    MERGE / verificação de existência).

    NOTA: este script é o schema-alvo; o `orchestrator` já liga a ele a
    sério via EF Core (ver ARCHITECTURE.md ADR-012) — validado contra
    uma instância real (Docker, só para desenvolvimento/teste). Ainda
    falta a connection string do servidor real do cliente para
    produção.

    Convenção de nomes: ter, us, alv, cestos, missao, sl, sa e cm
    correspondem aos códigos pedidos explicitamente pelo cliente (TER,
    US, ALV, CESTOS, MISSAO, SL, SA, CM) — o código mantém-se, mas
    todas as tabelas (incluindo estas) passaram a minúsculas por
    convenção própria (ADR-031), decisão do cliente. As restantes
    tabelas (incluindo artigos, ordenspreparacao, plataformas) usam
    nomes descritivos por não terem código pedido.
*/

SET NOCOUNT ON;
GO

-- Necessário para a coluna calculada/persistida em CM (regra de negócio
-- validada a correr este script contra uma instância real — sqlcmd não
-- garante isto ligado por omissão).
SET QUOTED_IDENTIFIER ON;
GO

-------------------------------------------------------------------------
-- 1. Base de dados
-------------------------------------------------------------------------

IF DB_ID(N'WOPA') IS NULL
BEGIN
    CREATE DATABASE WOPA;
END
GO

USE WOPA;
GO

-------------------------------------------------------------------------
-- 2. Zonas
--    Zonas do armazém (GET /api/zonas).
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'zonas' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.zonas
    (
        Id      NVARCHAR(50)  NOT NULL PRIMARY KEY,
        Codigo  NVARCHAR(20)  NOT NULL,
        Nome    NVARCHAR(100) NOT NULL
    );
END
GO

-------------------------------------------------------------------------
-- 3. Modulos
--    Módulos disponíveis no pda (GET /api/modulos).
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'modulos' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.modulos
    (
        Slug        NVARCHAR(50)  NOT NULL PRIMARY KEY,
        Nome        NVARCHAR(100) NOT NULL,
        Disponivel  BIT           NOT NULL DEFAULT (0)
    );
END
GO

-------------------------------------------------------------------------
-- 4. TER — Terminais
--    Um registo por PDA/dispositivo.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'ter' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.ter
    (
        Id                NVARCHAR(50)  NOT NULL PRIMARY KEY,   -- TER_ID
        Codigo            NVARCHAR(30)  NOT NULL UNIQUE,        -- TER_Codigo, ex. "PDA-001"
        Descricao         NVARCHAR(100) NULL,
        Ativo             BIT           NOT NULL DEFAULT (1),
        UltimoAcessoEm    DATETIME2     NULL
    );
END
GO

-------------------------------------------------------------------------
-- 5. US — Utilizadores
--    Operadores — hoje o pda só pede um "número de operador" no login
--    sem validar contra nada; esta tabela é o destino real dessa
--    validação (ver ARCHITECTURE.md secção 8).
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'us' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.us
    (
        Id                NVARCHAR(50)  NOT NULL PRIMARY KEY,   -- US_ID
        NumeroOperador    NVARCHAR(20)  NOT NULL UNIQUE,        -- US_Numero, o que se digita no pda
        Pin               NVARCHAR(255) NOT NULL,               -- texto na PoC; hash antes de produção (ver ARCHITECTURE.md secção 8)
        Nome              NVARCHAR(100) NOT NULL,
        Ativo             BIT           NOT NULL DEFAULT (1)
    );
END
GO

-------------------------------------------------------------------------
-- 6. ALV — Alvéolos
--    Localização física dentro de uma zona.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'alv' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.alv
    (
        Id        NVARCHAR(50)  NOT NULL PRIMARY KEY,   -- ALV_ID
        Codigo    NVARCHAR(30)  NOT NULL UNIQUE,         -- ALV_Codigo, ex. "A-01-03"
        ZonaId    NVARCHAR(50)  NOT NULL,
        Ativo     BIT           NOT NULL DEFAULT (1),

        CONSTRAINT FK_ALV_Zona FOREIGN KEY (ZonaId) REFERENCES dbo.zonas (Id)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ALV_ZonaId' AND object_id = OBJECT_ID(N'dbo.alv'))
    CREATE INDEX IX_ALV_ZonaId ON dbo.alv (ZonaId);
GO

-------------------------------------------------------------------------
-- 7. CESTOS
--    Tipos de cesto: dimensões e quantos cabem numa palete.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'cestos' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.cestos
    (
        Id                    NVARCHAR(50)  NOT NULL PRIMARY KEY,
        Codigo                NVARCHAR(30)  NOT NULL UNIQUE,
        ComprimentoMm         INT           NOT NULL,
        LarguraMm             INT           NOT NULL,
        AlturaMm              INT           NOT NULL,
        QuantidadePorPalete   INT           NOT NULL   -- quantos cestos deste tipo cabem numa palete
    );
END
GO

-------------------------------------------------------------------------
-- 8. Artigos
--    Dados mestre de artigo (RF-ENT-03) — base da cubicagem (Anexo
--    A.1) e do teste de qualidade de ficha (A.6). Recebidos via
--    integração com o ERP, tal como as Ordens de Preparação — ver
--    POST /api/artigos.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'artigos' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.artigos
    (
        Sku                       NVARCHAR(50)   NOT NULL PRIMARY KEY,
        Ean                       NVARCHAR(20)   NULL,
        Descricao                 NVARCHAR(200)  NOT NULL,
        UnidadesPorCaixa          INT            NULL,          -- u_EMBPECAS (A.1); NULL/<=0 => SEM_EMB (A.6)
        ComprimentoCaixaCm        DECIMAL(6,2)   NULL,           -- u_Ecomp
        LarguraCaixaCm            DECIMAL(6,2)   NULL,           -- u_Elarg
        AlturaCaixaCm             DECIMAL(6,2)   NULL,           -- u_Ealt
        PesoUnitarioKg            DECIMAL(8,3)   NULL,
        -- Pesado | Leve (A.8); NULL => SEM_CLASSE (A.6), impede empilhamento correto
        ClasseEmpilhamento        NVARCHAR(10)   NULL,
        CaixasPorPaleteCompleta   INT            NULL            -- para extração P0 (A.3); NULL => não se extrai P0 desta referência
    );
END
GO

-------------------------------------------------------------------------
-- 9. TiposPlataforma
--    P0 = palete completa (fluxo direto reserva->expedição, sem
--    passar pelos corredores — Anexo A.3), altura 1,30 m, sem cestos.
--    P1/P2/P4 = plataforma com 1/2/4 cestos, altura real 0,40 m
--    (corrigida pelo cliente — o v0.4 assumia 0,50 m). Capacidades
--    úteis recalculadas com a mesma fórmula da secção 4.7 do v0.4
--    (bruto × 0,80 de margem) para a altura real — ver ARCHITECTURE.md
--    ADR-017.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'tiposplataforma' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.tiposplataforma
    (
        Codigo                NVARCHAR(10)  NOT NULL PRIMARY KEY,  -- P0, P1, P2, P4
        Descricao             NVARCHAR(100) NOT NULL,
        ComprimentoMm         INT           NOT NULL,
        LarguraMm             INT           NOT NULL,
        AlturaMm              INT           NOT NULL,
        CestosPorPlataforma   INT           NOT NULL DEFAULT (0),  -- 0 para P0 (palete completa, sem cestos)
        -- 0 para P0: não participa na tipificação por volume (A.4) —
        -- é extraído antes, por múltiplos de palete completa (A.3).
        CapacidadeUtilLitros  INT           NOT NULL DEFAULT (0)
    );
END
GO

-------------------------------------------------------------------------
-- 10. CM — Código de Movimentos de Stock
--     Regra do cliente: CM_ID < 500 é entrada de stock,
--     CM_ID > 500 é saída — refletida diretamente numa coluna
--     calculada, para não depender de aplicações externas acertarem a
--     regra sempre da mesma forma. (CM_ID = 500 fica indefinido de
--     propósito — evitar usar esse valor.)
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'cm' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.cm
    (
        Id          INT           NOT NULL PRIMARY KEY,   -- CM_ID
        Descricao   NVARCHAR(100) NOT NULL,
        Tipo AS (CASE WHEN Id < 500 THEN N'Entrada' WHEN Id > 500 THEN N'Saida' ELSE N'Indefinido' END) PERSISTED
    );
END
GO

-------------------------------------------------------------------------
-- 11. RegrasMissao (ADR-010)
--     Regras de negócio para o controller criar missões — versão
--     básica proposta, ainda por validar com o cliente.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'regrasmissao' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.regrasmissao
    (
        Id                        INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        Chave                     NVARCHAR(50)  NOT NULL UNIQUE,
        MaxLinhasPorMissao        INT           NOT NULL DEFAULT (20),
        MaxPlataformasPorMissao   INT           NOT NULL DEFAULT (4),
        -- Zona | Encomenda | Nenhum
        CriterioAgrupamento       NVARCHAR(30)  NOT NULL DEFAULT (N'Zona'),
        -- Localizacao | Prioridade
        CriterioOrdenacao         NVARCHAR(30)  NOT NULL DEFAULT (N'Localizacao'),
        AtualizadoEm              DATETIME2     NOT NULL DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT CK_RegrasMissao_MaxLinhas CHECK (MaxLinhasPorMissao >= 1),
        CONSTRAINT CK_RegrasMissao_MaxPlataformas CHECK (MaxPlataformasPorMissao >= 1)
    );
END
GO

-------------------------------------------------------------------------
-- 12. OrdensPreparacao
--     "Ordem de preparação" do documento de requisitos v0.4: chega já
--     composta de outro software (agrupamento de PS por
--     cliente/data/morada já feito lá) — o WOPA só a recebe e guarda
--     via POST /api/ordens-preparacao. É a partir daqui que o WOPA
--     trata das etapas seguintes: cubicar, tipificar (gerar
--     Plataformas) e despachar (RF-CTL-01/05/06) — ver ARCHITECTURE.md
--     ADR-017.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'ordenspreparacao' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.ordenspreparacao
    (
        Id              NVARCHAR(50)  NOT NULL PRIMARY KEY,
        Cliente         NVARCHAR(200) NOT NULL,
        DataEntrega     DATE          NULL,
        MoradaEntrega   NVARCHAR(300) NULL,
        -- Aberta | Tipificada | Despachada
        Estado          NVARCHAR(20)  NOT NULL DEFAULT (N'Aberta'),
        AlturaPaleteCm  DECIMAL(6,2)  NULL,     -- RF-CTL-05 — determina o padrão de empilhamento (A.8)
        RecebidaEm      DATETIME2     NOT NULL DEFAULT (SYSUTCDATETIME())
    );
END
GO

-------------------------------------------------------------------------
-- 13. Plataformas
--     Geradas pela tipificação de uma Ordem de Preparação (Anexo
--     A.4/A.5). Uma ordem ≥P1 gera várias plataformas mono-ordem,
--     cada uma com o seu índice de camada (A.8) — a composição
--     partilhada de plataformas P2/P4 (Cenário B, Fase 2 do v0.4)
--     ainda não é gerada por este motor, ver ARCHITECTURE.md secção 8.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'plataformas' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.plataformas
    (
        Id                    NVARCHAR(50)  NOT NULL PRIMARY KEY,
        Codigo                NVARCHAR(30)  NOT NULL,
        OrdemPreparacaoId     NVARCHAR(50)  NULL,
        TipoPlataformaCodigo  NVARCHAR(10)  NOT NULL,
        IndiceCamada          INT           NULL,      -- 1 = base (A.8); só ordens >=P1 com várias plataformas
        -- Pesada | Leve
        ClasseCamada          NVARCHAR(10)  NULL,
        CelulaDestino         NVARCHAR(50)  NULL,       -- RF-CTL-06
        -- EmPicking | NoBuffer | EmPacking | Concluida
        Estado                NVARCHAR(20)  NOT NULL DEFAULT (N'EmPicking'),
        CriadaEm              DATETIME2     NOT NULL DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT FK_Plataformas_OrdemPreparacao FOREIGN KEY (OrdemPreparacaoId) REFERENCES dbo.ordenspreparacao (Id),
        CONSTRAINT FK_Plataformas_Tipo FOREIGN KEY (TipoPlataformaCodigo) REFERENCES dbo.tiposplataforma (Codigo)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Plataformas_OrdemPreparacaoId' AND object_id = OBJECT_ID(N'dbo.plataformas'))
    CREATE INDEX IX_Plataformas_OrdemPreparacaoId ON dbo.plataformas (OrdemPreparacaoId);
GO

-------------------------------------------------------------------------
-- 14. OrdensSeparacao + OrdensSeparacaoLinhas
--     "PS" (pedido de separação) do documento de requisitos v0.4:
--     chegam sempre dentro de uma Ordem de Preparação já composta (ver
--     tabela 12) — não há um fluxo separado de PS "soltos" à espera de
--     agrupamento no WOPA.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'ordensseparacao' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.ordensseparacao
    (
        Id                  NVARCHAR(50)  NOT NULL PRIMARY KEY,
        OrdemPreparacaoId   NVARCHAR(50)  NOT NULL,
        NumeroDocumento     NVARCHAR(50)  NOT NULL,
        -- PHC | OrdersHub | ... (a confirmar — ADR-008)
        Origem              NVARCHAR(20)  NOT NULL,
        -- ONLINE | B2B | FISICAS | CNUS (secção 2.1)
        Canal               NVARCHAR(20)  NULL,
        RecebidaEm          DATETIME2     NOT NULL DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT FK_OrdensSeparacao_OrdemPreparacao FOREIGN KEY (OrdemPreparacaoId) REFERENCES dbo.ordenspreparacao (Id)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_OrdensSeparacao_OrdemPreparacaoId' AND object_id = OBJECT_ID(N'dbo.ordensseparacao'))
    CREATE INDEX IX_OrdensSeparacao_OrdemPreparacaoId ON dbo.ordensseparacao (OrdemPreparacaoId);
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'ordensseparacaolinhas' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.ordensseparacaolinhas
    (
        Id                  NVARCHAR(50)  NOT NULL PRIMARY KEY,
        OrdemSeparacaoId    NVARCHAR(50)  NOT NULL,
        Sku                 NVARCHAR(50)  NOT NULL,
        Quantidade          INT           NOT NULL,
        AlveoloId           NVARCHAR(50)  NULL,
        -- Atribuída pela tipificação (A.5): a que plataforma esta linha
        -- foi destinada. Distribuição round-robin quando a ordem gera
        -- várias plataformas — simplificação da PoC, ver
        -- ARCHITECTURE.md secção 8.
        PlataformaId        NVARCHAR(50)  NULL,

        CONSTRAINT FK_OrdensSeparacaoLinhas_Ordem FOREIGN KEY (OrdemSeparacaoId) REFERENCES dbo.ordensseparacao (Id),
        CONSTRAINT FK_OrdensSeparacaoLinhas_Alveolo FOREIGN KEY (AlveoloId) REFERENCES dbo.alv (Id),
        CONSTRAINT FK_OrdensSeparacaoLinhas_Plataforma FOREIGN KEY (PlataformaId) REFERENCES dbo.plataformas (Id),
        CONSTRAINT CK_OrdensSeparacaoLinhas_Quantidade CHECK (Quantidade > 0)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_OrdensSeparacaoLinhas_OrdemId' AND object_id = OBJECT_ID(N'dbo.ordensseparacaolinhas'))
    CREATE INDEX IX_OrdensSeparacaoLinhas_OrdemId ON dbo.ordensseparacaolinhas (OrdemSeparacaoId);
GO

-------------------------------------------------------------------------
-- 15. MISSAO
--     Cobre os seis centros de trabalho do v0.4 (secção 4.5): picking,
--     packing, transporte, abastecimento, reposição, P0 — só o motor
--     de picking está implementado por agora (ver ARCHITECTURE.md
--     secção 8). Estados e motivos de pausa seguem A.13.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'missao' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.missao
    (
        Id              NVARCHAR(50)  NOT NULL PRIMARY KEY,
        Codigo          NVARCHAR(30)  NOT NULL,
        -- Picking | Packing | Transporte | Abastecimento | Reposicao | P0
        CentroTrabalho  NVARCHAR(20)  NOT NULL DEFAULT (N'Picking'),
        ZonaId          NVARCHAR(50)  NULL,
        PlataformaId    NVARCHAR(50)  NULL,
        UtilizadorId    NVARCHAR(50)  NULL,   -- operador a quem a missão está atribuída
        TerminalId      NVARCHAR(50)  NULL,   -- PDA que a está a executar
        -- Planeada | Criada | Atribuida | EmExecucao | Pausada | Concluida | FechadaIncompleta
        -- (A.13 + ADR-027: "Planeada" é novo -- despacho com data futura,
        -- ver DataPlaneada abaixo; só entra no circuito normal quando o
        -- dia chega, tratado como "Criada" a partir daí)
        Estado          NVARCHAR(20)  NOT NULL DEFAULT (N'Criada'),
        -- Rutura | FimTurno | MudancaPrioridade | Avaria (A.13)
        MotivoPausa     NVARCHAR(30)  NULL,
        CriadaEm        DATETIME2     NOT NULL DEFAULT (SYSUTCDATETIME()),
        AtribuidaEm     DATETIME2     NULL,
        IniciadaEm      DATETIME2     NULL,
        PausadaEm       DATETIME2     NULL,
        RetomadaEm      DATETIME2     NULL,
        ConcluidaEm     DATETIME2     NULL,

        CONSTRAINT FK_MISSAO_Zona FOREIGN KEY (ZonaId) REFERENCES dbo.zonas (Id),
        CONSTRAINT FK_MISSAO_Plataforma FOREIGN KEY (PlataformaId) REFERENCES dbo.plataformas (Id),
        CONSTRAINT FK_MISSAO_Utilizador FOREIGN KEY (UtilizadorId) REFERENCES dbo.us (Id),
        CONSTRAINT FK_MISSAO_Terminal FOREIGN KEY (TerminalId) REFERENCES dbo.ter (Id)
    );
END
GO

-------------------------------------------------------------------------
-- 16. MissaoLinhas
--     Uma linha por artigo a picar dentro de uma missão. Corresponde a
--     GET /api/picking/tasks — com alvéolo, tipo de plataforma e
--     cestos necessários, em vez de localização em texto livre. (O
--     cliente não pediu um nome de tabela específico para as linhas,
--     só para o cabeçalho MISSAO — nome descritivo mantido aqui.)
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'missaolinhas' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.missaolinhas
    (
        Id                     NVARCHAR(50)   NOT NULL PRIMARY KEY,
        MissaoId               NVARCHAR(50)   NOT NULL,
        Sku                    NVARCHAR(50)   NOT NULL,   -- artigo
        Descricao              NVARCHAR(200)  NOT NULL,
        CodigoBarras           NVARCHAR(50)   NOT NULL,
        AlveoloId              NVARCHAR(50)   NULL,       -- de onde se pica; NULL para zonas sem detalhe de alvéolo (ex.: Armazém Automático — ver ARCHITECTURE.md secção 4.6)
        Plataforma             NVARCHAR(30)   NOT NULL,   -- identificador da palete/tote de destino desta missão
        TipoPlataformaCodigo   NVARCHAR(10)   NOT NULL,   -- P0 | P1 | P2 | P4
        CestoId                NVARCHAR(50)   NULL,
        CestosNecessarios      INT            NOT NULL DEFAULT (0),
        QuantidadeAlvo         INT            NOT NULL,
        QuantidadeLida         INT            NOT NULL DEFAULT (0),
        -- Pendente | EmProgresso | Concluida
        Estado                 NVARCHAR(20)   NOT NULL DEFAULT (N'Pendente'),

        CONSTRAINT FK_MissaoLinhas_Missao FOREIGN KEY (MissaoId) REFERENCES dbo.missao (Id),
        CONSTRAINT FK_MissaoLinhas_Alveolo FOREIGN KEY (AlveoloId) REFERENCES dbo.alv (Id),
        CONSTRAINT FK_MissaoLinhas_TipoPlataforma FOREIGN KEY (TipoPlataformaCodigo) REFERENCES dbo.tiposplataforma (Codigo),
        CONSTRAINT FK_MissaoLinhas_Cesto FOREIGN KEY (CestoId) REFERENCES dbo.cestos (Id),
        CONSTRAINT CK_MissaoLinhas_Quantidade CHECK (QuantidadeLida >= 0 AND QuantidadeLida <= QuantidadeAlvo)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_MissaoLinhas_MissaoId' AND object_id = OBJECT_ID(N'dbo.missaolinhas'))
    CREATE INDEX IX_MissaoLinhas_MissaoId ON dbo.missaolinhas (MissaoId);
GO

-------------------------------------------------------------------------
-- 17. OperacoesProcessadas
--     Idempotência das operações vindas de PDAs offline (ADR-007).
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'operacoesprocessadas' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.operacoesprocessadas
    (
        OperacaoId      NVARCHAR(50)  NOT NULL PRIMARY KEY,
        MissaoLinhaId   NVARCHAR(50)  NOT NULL,
        -- scan | confirm
        Tipo            NVARCHAR(20)  NOT NULL,
        ProcessadoEm    DATETIME2     NOT NULL DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT FK_OperacoesProcessadas_Linha FOREIGN KEY (MissaoLinhaId) REFERENCES dbo.missaolinhas (Id)
    );
END
GO

-------------------------------------------------------------------------
-- 18. SL — Movimentos de Stock
--     Ledger de movimentos — cada picking confirmado gera aqui um
--     movimento de saída (CM_ID > 500).
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'sl' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.sl
    (
        Id                  BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        CodigoMovimentoId   INT            NOT NULL,
        Sku                 NVARCHAR(50)   NOT NULL,
        AlveoloId           NVARCHAR(50)   NOT NULL,
        Quantidade          INT            NOT NULL,   -- sempre positivo; o sinal vem do CodigoMovimentoId
        MissaoLinhaId       NVARCHAR(50)   NULL,        -- preenchido quando o movimento vem de um picking
        CriadoEm            DATETIME2      NOT NULL DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT FK_SL_Codigo FOREIGN KEY (CodigoMovimentoId) REFERENCES dbo.cm (Id),
        CONSTRAINT FK_SL_Alveolo FOREIGN KEY (AlveoloId) REFERENCES dbo.alv (Id),
        CONSTRAINT FK_SL_MissaoLinha FOREIGN KEY (MissaoLinhaId) REFERENCES dbo.missaolinhas (Id),
        CONSTRAINT CK_SL_Quantidade CHECK (Quantidade > 0)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_SL_Sku_Alveolo' AND object_id = OBJECT_ID(N'dbo.sl'))
    CREATE INDEX IX_SL_Sku_Alveolo ON dbo.sl (Sku, AlveoloId);
GO

-------------------------------------------------------------------------
-- 19. SA — Stock por Armazém e Alvéolo
--     Quantidade atual por artigo e alvéolo — a "fotografia" que o
--     SL (18) vai atualizando ao longo do tempo.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'sa' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.sa
    (
        Sku            NVARCHAR(50)  NOT NULL,
        AlveoloId      NVARCHAR(50)  NOT NULL,
        Quantidade     INT           NOT NULL DEFAULT (0),
        AtualizadoEm   DATETIME2     NOT NULL DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_SA PRIMARY KEY (Sku, AlveoloId),
        CONSTRAINT FK_SA_Alveolo FOREIGN KEY (AlveoloId) REFERENCES dbo.alv (Id),
        CONSTRAINT CK_SA_Quantidade CHECK (Quantidade >= 0)
    );
END
GO

-------------------------------------------------------------------------
-- 20. Seed — dados de referência/configuração (ADR-031). Só o que o
--     próprio WOPA precisa para funcionar (módulos, tipos de
--     plataforma/cesto, códigos de movimento, regra de missão
--     por omissão) — os dados de negócio (zonas, alvéolos, artigos,
--     ordens, missões) deixaram de ser semeados aqui: a partir de
--     agora vêm todos de dados reais, geridos como qualquer outro
--     registo.
-------------------------------------------------------------------------

MERGE dbo.modulos AS alvo
USING (VALUES
    (N'picking',       N'Picking',       CAST(1 AS BIT)),
    (N'transporte',     N'Transporte',     CAST(0 AS BIT)),
    (N'abastecimento',  N'Abastecimento',  CAST(0 AS BIT))
) AS novo (Slug, Nome, Disponivel)
ON alvo.Slug = novo.Slug
WHEN NOT MATCHED THEN
    INSERT (Slug, Nome, Disponivel) VALUES (novo.Slug, novo.Nome, novo.Disponivel);
GO

-- Dimensões de exemplo (mm) — por confirmar com o cliente.
MERGE dbo.cestos AS alvo
USING (VALUES
    (N'cesto-standard', N'CESTO-STD', 600, 400, 300, 4)
) AS novo (Id, Codigo, ComprimentoMm, LarguraMm, AlturaMm, QuantidadePorPalete)
ON alvo.Id = novo.Id
WHEN NOT MATCHED THEN
    INSERT (Id, Codigo, ComprimentoMm, LarguraMm, AlturaMm, QuantidadePorPalete)
    VALUES (novo.Id, novo.Codigo, novo.ComprimentoMm, novo.LarguraMm, novo.AlturaMm, novo.QuantidadePorPalete);
GO

-- Dimensões confirmadas pelo cliente: P0 (palete completa) 1,30 m de
-- altura, sem cestos. P1/P2/P4 (cesto físico) 0,40 m de altura própria
-- — mas ver ADR-018: a query real de tipificação do cliente (a que
-- gera as Ordens de Preparação) usa 96000/192000/384000 cm³ como
-- limiares, que só batem certo com uma altura ÚTIL DE CARGA de 50 cm
-- (limite de alcance do operador sobre o cesto — distinto da altura
-- física do cesto em si). Por isso CapacidadeUtilLitros mantém-se nos
-- valores validados pela query real (384/192/96 L); AlturaMm regista
-- a altura física do cesto (40 cm) tal como o cliente a deu, sem
-- influenciar a capacidade — são duas medidas diferentes, não a mesma
-- corrigida duas vezes. Ver ARCHITECTURE.md ADR-018 para a
-- reconciliação e o que fica por confirmar.
MERGE dbo.tiposplataforma AS alvo
USING (VALUES
    (N'P0', N'Palete completa (fluxo direto)',   1200, 800, 1300, 0,   0),
    (N'P1', N'Plataforma + 1 cesto (120x80cm)',  1200, 800,  400, 1, 384),
    (N'P2', N'Plataforma + 2 cestos (60x80cm)',   600, 800,  400, 2, 192),
    (N'P4', N'Plataforma + 4 cestos (40x60cm)',   400, 600,  400, 4,  96)
) AS novo (Codigo, Descricao, ComprimentoMm, LarguraMm, AlturaMm, CestosPorPlataforma, CapacidadeUtilLitros)
ON alvo.Codigo = novo.Codigo
WHEN NOT MATCHED THEN
    INSERT (Codigo, Descricao, ComprimentoMm, LarguraMm, AlturaMm, CestosPorPlataforma, CapacidadeUtilLitros)
    VALUES (novo.Codigo, novo.Descricao, novo.ComprimentoMm, novo.LarguraMm, novo.AlturaMm, novo.CestosPorPlataforma, novo.CapacidadeUtilLitros);
GO

MERGE dbo.cm AS alvo
USING (VALUES
    (100, N'Entrada por compra'),
    (110, N'Entrada por devolução de cliente'),
    (501, N'Saída por picking'),
    (510, N'Saída por quebra')
) AS novo (Id, Descricao)
ON alvo.Id = novo.Id
WHEN MATCHED THEN
    UPDATE SET Descricao = novo.Descricao
WHEN NOT MATCHED THEN
    INSERT (Id, Descricao) VALUES (novo.Id, novo.Descricao);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.regrasmissao WHERE Chave = N'default')
BEGIN
    INSERT INTO dbo.regrasmissao (Chave, MaxLinhasPorMissao, MaxPlataformasPorMissao, CriterioAgrupamento, CriterioOrdenacao)
    VALUES (N'default', 20, 4, N'Zona', N'Localizacao');
END
GO

-------------------------------------------------------------------------
-- 21. Celulas — recurso de capacidade (packing/montagem/consolidação),
--     ADR-027. Capacidade diária simples (constante por célula) para
--     arrancar — não um calendário completo; afina-se com histórico ao
--     fim de 3-6 meses, tal como discutido com o cliente.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'celulas' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.celulas
    (
        Id                       NVARCHAR(50)  NOT NULL PRIMARY KEY,
        Codigo                   NVARCHAR(30)  NOT NULL,
        Nome                     NVARCHAR(100) NOT NULL,
        CapacidadeDiariaUnidades INT           NOT NULL DEFAULT (0),
        Ativa                    BIT           NOT NULL DEFAULT (1)
    );
END
GO

-------------------------------------------------------------------------
-- 22. Migrações aditivas (ADR-027) — colunas novas em tabelas já
--     existentes em produção. Ao contrário do resto deste ficheiro
--     ("clean script", ADR-017), isto usa ALTER TABLE porque já existe
--     uma BD real no cliente sem estas colunas — um CREATE TABLE IF NOT
--     EXISTS não as acrescentaria retroativamente. Guardado por
--     existência da coluna, para poder correr outra vez em segurança.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.missao') AND name = N'DataPlaneada')
    ALTER TABLE dbo.missao ADD DataPlaneada DATE NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.missao') AND name = N'CelulaId')
    ALTER TABLE dbo.missao ADD CelulaId NVARCHAR(50) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_MISSAO_Celula')
    ALTER TABLE dbo.missao ADD CONSTRAINT FK_MISSAO_Celula FOREIGN KEY (CelulaId) REFERENCES dbo.celulas (Id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.ordenspreparacao') AND name = N'Urgente')
    ALTER TABLE dbo.ordenspreparacao ADD Urgente BIT NOT NULL DEFAULT (0);
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.ordenspreparacao') AND name = N'DataLimite')
    ALTER TABLE dbo.ordenspreparacao ADD DataLimite DATETIME2 NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.sl') AND name = N'Motivo')
    ALTER TABLE dbo.sl ADD Motivo NVARCHAR(50) NULL;
GO

-------------------------------------------------------------------------
-- 23. Seed — Celulas de exemplo.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM dbo.celulas WHERE Id = N'celula-1')
    INSERT INTO dbo.celulas (Id, Codigo, Nome, CapacidadeDiariaUnidades) VALUES (N'celula-1', N'CELULA-1', N'Célula 1', 500);
IF NOT EXISTS (SELECT 1 FROM dbo.celulas WHERE Id = N'celula-2')
    INSERT INTO dbo.celulas (Id, Codigo, Nome, CapacidadeDiariaUnidades) VALUES (N'celula-2', N'CELULA-2', N'Célula 2', 500);
GO

-------------------------------------------------------------------------
-- 24. PlataformaCestos (ADR-029) — matrículas dos cestos montados numa
--     plataforma (P1/P2/P4). Uma linha por cesto físico associado; P0
--     nunca tem linhas aqui (CestosPorPlataforma = 0). Ver secção 25
--     para o resto do gate de montagem.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'plataformacestos' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.plataformacestos
    (
        Id             NVARCHAR(50)  NOT NULL PRIMARY KEY,
        PlataformaId   NVARCHAR(50)  NOT NULL,
        MatriculaCesto NVARCHAR(50)  NOT NULL,
        CriadoEm       DATETIME2     NOT NULL DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT FK_PlataformaCestos_Plataforma FOREIGN KEY (PlataformaId) REFERENCES dbo.plataformas (Id),
        CONSTRAINT UQ_PlataformaCestos_Matricula UNIQUE (PlataformaId, MatriculaCesto)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_PlataformaCestos_PlataformaId' AND object_id = OBJECT_ID(N'dbo.plataformacestos'))
    CREATE INDEX IX_PlataformaCestos_PlataformaId ON dbo.plataformacestos (PlataformaId);
GO

-------------------------------------------------------------------------
-- 25. Migrações aditivas (ADR-029) — gate de montagem no picking: não é
--     possível iniciar o picking de artigos de uma missão sem primeiro
--     indicar a plataforma (palete + cestos, conforme o tipo). A
--     primeira zona de uma Ordem monta a plataforma de raiz; zonas
--     seguintes só confirmam que é a mesma (ver PickingEndpoints).
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.plataformas') AND name = N'MatriculaPalete')
    ALTER TABLE dbo.plataformas ADD MatriculaPalete NVARCHAR(50) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.plataformas') AND name = N'MontadaEm')
    ALTER TABLE dbo.plataformas ADD MontadaEm DATETIME2 NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.missao') AND name = N'PlataformaConfirmada')
    ALTER TABLE dbo.missao ADD PlataformaConfirmada BIT NOT NULL DEFAULT (0);
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.missao') AND name = N'PlataformaConfirmadaEm')
    ALTER TABLE dbo.missao ADD PlataformaConfirmadaEm DATETIME2 NULL;
GO

-------------------------------------------------------------------------
-- 26. Migrações aditivas (ADR-030) — ALV: tipo de alvéolo (picking,
--     reserva, depósito de equipamento vazio, buffer de packing) e
--     posição estruturada (corredor/coluna/nível) para sequenciar rota
--     de picking, em vez de só o Codigo em texto livre.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.alv') AND name = N'Tipo')
    -- Picking | Reserva | Deposito | Buffer
    ALTER TABLE dbo.alv ADD Tipo NVARCHAR(20) NOT NULL DEFAULT (N'Picking');
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.alv') AND name = N'Corredor')
    ALTER TABLE dbo.alv ADD Corredor NVARCHAR(10) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.alv') AND name = N'Coluna')
    ALTER TABLE dbo.alv ADD Coluna INT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.alv') AND name = N'Nivel')
    ALTER TABLE dbo.alv ADD Nivel INT NULL;
GO

-------------------------------------------------------------------------
-- 27. CestoInstancias (ADR-030) — cesto físico com matrícula própria,
--     equipamento reutilizável (CESTOS continua a ser só o tipo/spec).
--     Estado Livre = no depósito, à espera de ser montado numa
--     plataforma; EmUso = montado, em circulação (sem alvéolo fixo
--     enquanto isso). Criada pelo próprio gate de montagem do picking
--     (ver PickingEndpoints) na primeira vez que lê cada matrícula --
--     ainda não há um fluxo de pré-registo de equipamento à parte.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'cestoinstancias' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.cestoinstancias
    (
        Id                 NVARCHAR(50)  NOT NULL PRIMARY KEY,
        Matricula          NVARCHAR(50)  NOT NULL UNIQUE,
        TipoCestoId        NVARCHAR(50)  NOT NULL,
        -- Livre | EmUso
        Estado             NVARCHAR(20)  NOT NULL DEFAULT (N'Livre'),
        LocalizacaoAtualId NVARCHAR(50)  NULL,
        CriadoEm           DATETIME2     NOT NULL DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT FK_CestoInstancias_Tipo FOREIGN KEY (TipoCestoId) REFERENCES dbo.cestos (Id),
        CONSTRAINT FK_CestoInstancias_Localizacao FOREIGN KEY (LocalizacaoAtualId) REFERENCES dbo.alv (Id)
    );
END
GO

-------------------------------------------------------------------------
-- 28. Migrações aditivas (ADR-032) — ordenspreparacao ganha campos da
--     query real de tipificação do PHC (cliente confirmou: a
--     Ordem já chega tipificada de lá — TipoPlataformaCodigo/
--     NPlataformas passam a poder vir prontos, sem o WOPA recalcular
--     por cubicagem). Os restantes campos (NumeroOrdem/NumeroPedido/
--     NumeroProforma/NumRefs/TotalCaixas/VolumeTotalCm3/PesoTotalKg/
--     RefsSemFicha/Observacoes) são só para rastreabilidade contra a
--     origem -- ver ARCHITECTURE.md ADR-032.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.ordenspreparacao') AND name = N'ReferenciaExterna')
    ALTER TABLE dbo.ordenspreparacao ADD ReferenciaExterna NVARCHAR(50) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UQ_ordenspreparacao_ReferenciaExterna' AND object_id = OBJECT_ID(N'dbo.ordenspreparacao'))
    CREATE UNIQUE INDEX UQ_ordenspreparacao_ReferenciaExterna ON dbo.ordenspreparacao (ReferenciaExterna) WHERE ReferenciaExterna IS NOT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.ordenspreparacao') AND name = N'NumeroOrdem')
    ALTER TABLE dbo.ordenspreparacao ADD NumeroOrdem INT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.ordenspreparacao') AND name = N'NumeroPedido')
    ALTER TABLE dbo.ordenspreparacao ADD NumeroPedido INT NULL;
GO

-- numpf na origem -- número de proforma/encomenda (ADR-032).
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.ordenspreparacao') AND name = N'NumeroProforma')
    ALTER TABLE dbo.ordenspreparacao ADD NumeroProforma INT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.ordenspreparacao') AND name = N'TipoPlataformaCodigo')
    ALTER TABLE dbo.ordenspreparacao ADD TipoPlataformaCodigo NVARCHAR(10) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_ordenspreparacao_TipoPlataforma')
    ALTER TABLE dbo.ordenspreparacao ADD CONSTRAINT FK_ordenspreparacao_TipoPlataforma FOREIGN KEY (TipoPlataformaCodigo) REFERENCES dbo.tiposplataforma (Codigo);
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.ordenspreparacao') AND name = N'NPlataformas')
    ALTER TABLE dbo.ordenspreparacao ADD NPlataformas INT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.ordenspreparacao') AND name = N'NumRefs')
    ALTER TABLE dbo.ordenspreparacao ADD NumRefs INT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.ordenspreparacao') AND name = N'TotalCaixas')
    ALTER TABLE dbo.ordenspreparacao ADD TotalCaixas INT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.ordenspreparacao') AND name = N'VolumeTotalCm3')
    ALTER TABLE dbo.ordenspreparacao ADD VolumeTotalCm3 DECIMAL(14,3) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.ordenspreparacao') AND name = N'PesoTotalKg')
    ALTER TABLE dbo.ordenspreparacao ADD PesoTotalKg DECIMAL(10,3) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.ordenspreparacao') AND name = N'RefsSemFicha')
    ALTER TABLE dbo.ordenspreparacao ADD RefsSemFicha INT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.ordenspreparacao') AND name = N'Observacoes')
    ALTER TABLE dbo.ordenspreparacao ADD Observacoes NVARCHAR(500) NULL;
GO

PRINT 'Base de dados WOPA pronta.';
GO
