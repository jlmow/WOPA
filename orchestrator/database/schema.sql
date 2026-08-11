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

    Convenção de nomes: TER, US, ALV, CESTOS, MISSAO, SL, SA e CM são
    nomes de tabela pedidos explicitamente pelo cliente (não apenas
    códigos de referência) — mantidos exatamente assim. As restantes
    tabelas (incluindo Artigos, OrdensPreparacao, Plataformas) usam
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

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'Zonas' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.Zonas
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

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'Modulos' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.Modulos
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

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'TER' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.TER
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

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'US' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.US
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

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'ALV' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.ALV
    (
        Id        NVARCHAR(50)  NOT NULL PRIMARY KEY,   -- ALV_ID
        Codigo    NVARCHAR(30)  NOT NULL UNIQUE,         -- ALV_Codigo, ex. "A-01-03"
        ZonaId    NVARCHAR(50)  NOT NULL,
        Ativo     BIT           NOT NULL DEFAULT (1),

        CONSTRAINT FK_ALV_Zona FOREIGN KEY (ZonaId) REFERENCES dbo.Zonas (Id)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_ALV_ZonaId' AND object_id = OBJECT_ID(N'dbo.ALV'))
    CREATE INDEX IX_ALV_ZonaId ON dbo.ALV (ZonaId);
GO

-------------------------------------------------------------------------
-- 7. CESTOS
--    Tipos de cesto: dimensões e quantos cabem numa palete.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'CESTOS' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.CESTOS
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

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'Artigos' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.Artigos
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

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'TiposPlataforma' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.TiposPlataforma
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

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'CM' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.CM
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

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'RegrasMissao' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.RegrasMissao
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

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'OrdensPreparacao' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.OrdensPreparacao
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

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'Plataformas' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.Plataformas
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

        CONSTRAINT FK_Plataformas_OrdemPreparacao FOREIGN KEY (OrdemPreparacaoId) REFERENCES dbo.OrdensPreparacao (Id),
        CONSTRAINT FK_Plataformas_Tipo FOREIGN KEY (TipoPlataformaCodigo) REFERENCES dbo.TiposPlataforma (Codigo)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Plataformas_OrdemPreparacaoId' AND object_id = OBJECT_ID(N'dbo.Plataformas'))
    CREATE INDEX IX_Plataformas_OrdemPreparacaoId ON dbo.Plataformas (OrdemPreparacaoId);
GO

-------------------------------------------------------------------------
-- 14. OrdensSeparacao + OrdensSeparacaoLinhas
--     "PS" (pedido de separação) do documento de requisitos v0.4:
--     chegam sempre dentro de uma Ordem de Preparação já composta (ver
--     tabela 12) — não há um fluxo separado de PS "soltos" à espera de
--     agrupamento no WOPA.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'OrdensSeparacao' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.OrdensSeparacao
    (
        Id                  NVARCHAR(50)  NOT NULL PRIMARY KEY,
        OrdemPreparacaoId   NVARCHAR(50)  NOT NULL,
        NumeroDocumento     NVARCHAR(50)  NOT NULL,
        -- PHC | OrdersHub | ... (a confirmar — ADR-008)
        Origem              NVARCHAR(20)  NOT NULL,
        -- ONLINE | B2B | FISICAS | CNUS (secção 2.1)
        Canal               NVARCHAR(20)  NULL,
        RecebidaEm          DATETIME2     NOT NULL DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT FK_OrdensSeparacao_OrdemPreparacao FOREIGN KEY (OrdemPreparacaoId) REFERENCES dbo.OrdensPreparacao (Id)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_OrdensSeparacao_OrdemPreparacaoId' AND object_id = OBJECT_ID(N'dbo.OrdensSeparacao'))
    CREATE INDEX IX_OrdensSeparacao_OrdemPreparacaoId ON dbo.OrdensSeparacao (OrdemPreparacaoId);
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'OrdensSeparacaoLinhas' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.OrdensSeparacaoLinhas
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

        CONSTRAINT FK_OrdensSeparacaoLinhas_Ordem FOREIGN KEY (OrdemSeparacaoId) REFERENCES dbo.OrdensSeparacao (Id),
        CONSTRAINT FK_OrdensSeparacaoLinhas_Alveolo FOREIGN KEY (AlveoloId) REFERENCES dbo.ALV (Id),
        CONSTRAINT FK_OrdensSeparacaoLinhas_Plataforma FOREIGN KEY (PlataformaId) REFERENCES dbo.Plataformas (Id),
        CONSTRAINT CK_OrdensSeparacaoLinhas_Quantidade CHECK (Quantidade > 0)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_OrdensSeparacaoLinhas_OrdemId' AND object_id = OBJECT_ID(N'dbo.OrdensSeparacaoLinhas'))
    CREATE INDEX IX_OrdensSeparacaoLinhas_OrdemId ON dbo.OrdensSeparacaoLinhas (OrdemSeparacaoId);
GO

-------------------------------------------------------------------------
-- 15. MISSAO
--     Cobre os seis centros de trabalho do v0.4 (secção 4.5): picking,
--     packing, transporte, abastecimento, reposição, P0 — só o motor
--     de picking está implementado por agora (ver ARCHITECTURE.md
--     secção 8). Estados e motivos de pausa seguem A.13.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'MISSAO' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.MISSAO
    (
        Id              NVARCHAR(50)  NOT NULL PRIMARY KEY,
        Codigo          NVARCHAR(30)  NOT NULL,
        -- Picking | Packing | Transporte | Abastecimento | Reposicao | P0
        CentroTrabalho  NVARCHAR(20)  NOT NULL DEFAULT (N'Picking'),
        ZonaId          NVARCHAR(50)  NULL,
        PlataformaId    NVARCHAR(50)  NULL,
        UtilizadorId    NVARCHAR(50)  NULL,   -- operador a quem a missão está atribuída
        TerminalId      NVARCHAR(50)  NULL,   -- PDA que a está a executar
        -- Criada | Atribuida | EmExecucao | Pausada | Concluida | FechadaIncompleta (A.13)
        Estado          NVARCHAR(20)  NOT NULL DEFAULT (N'Criada'),
        -- Rutura | FimTurno | MudancaPrioridade | Avaria (A.13)
        MotivoPausa     NVARCHAR(30)  NULL,
        CriadaEm        DATETIME2     NOT NULL DEFAULT (SYSUTCDATETIME()),
        AtribuidaEm     DATETIME2     NULL,
        IniciadaEm      DATETIME2     NULL,
        PausadaEm       DATETIME2     NULL,
        RetomadaEm      DATETIME2     NULL,
        ConcluidaEm     DATETIME2     NULL,

        CONSTRAINT FK_MISSAO_Zona FOREIGN KEY (ZonaId) REFERENCES dbo.Zonas (Id),
        CONSTRAINT FK_MISSAO_Plataforma FOREIGN KEY (PlataformaId) REFERENCES dbo.Plataformas (Id),
        CONSTRAINT FK_MISSAO_Utilizador FOREIGN KEY (UtilizadorId) REFERENCES dbo.US (Id),
        CONSTRAINT FK_MISSAO_Terminal FOREIGN KEY (TerminalId) REFERENCES dbo.TER (Id)
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

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'MissaoLinhas' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.MissaoLinhas
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

        CONSTRAINT FK_MissaoLinhas_Missao FOREIGN KEY (MissaoId) REFERENCES dbo.MISSAO (Id),
        CONSTRAINT FK_MissaoLinhas_Alveolo FOREIGN KEY (AlveoloId) REFERENCES dbo.ALV (Id),
        CONSTRAINT FK_MissaoLinhas_TipoPlataforma FOREIGN KEY (TipoPlataformaCodigo) REFERENCES dbo.TiposPlataforma (Codigo),
        CONSTRAINT FK_MissaoLinhas_Cesto FOREIGN KEY (CestoId) REFERENCES dbo.CESTOS (Id),
        CONSTRAINT CK_MissaoLinhas_Quantidade CHECK (QuantidadeLida >= 0 AND QuantidadeLida <= QuantidadeAlvo)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_MissaoLinhas_MissaoId' AND object_id = OBJECT_ID(N'dbo.MissaoLinhas'))
    CREATE INDEX IX_MissaoLinhas_MissaoId ON dbo.MissaoLinhas (MissaoId);
GO

-------------------------------------------------------------------------
-- 17. OperacoesProcessadas
--     Idempotência das operações vindas de PDAs offline (ADR-007).
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'OperacoesProcessadas' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.OperacoesProcessadas
    (
        OperacaoId      NVARCHAR(50)  NOT NULL PRIMARY KEY,
        MissaoLinhaId   NVARCHAR(50)  NOT NULL,
        -- scan | confirm
        Tipo            NVARCHAR(20)  NOT NULL,
        ProcessadoEm    DATETIME2     NOT NULL DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT FK_OperacoesProcessadas_Linha FOREIGN KEY (MissaoLinhaId) REFERENCES dbo.MissaoLinhas (Id)
    );
END
GO

-------------------------------------------------------------------------
-- 18. SL — Movimentos de Stock
--     Ledger de movimentos — cada picking confirmado gera aqui um
--     movimento de saída (CM_ID > 500).
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'SL' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.SL
    (
        Id                  BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        CodigoMovimentoId   INT            NOT NULL,
        Sku                 NVARCHAR(50)   NOT NULL,
        AlveoloId           NVARCHAR(50)   NOT NULL,
        Quantidade          INT            NOT NULL,   -- sempre positivo; o sinal vem do CodigoMovimentoId
        MissaoLinhaId       NVARCHAR(50)   NULL,        -- preenchido quando o movimento vem de um picking
        CriadoEm            DATETIME2      NOT NULL DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT FK_SL_Codigo FOREIGN KEY (CodigoMovimentoId) REFERENCES dbo.CM (Id),
        CONSTRAINT FK_SL_Alveolo FOREIGN KEY (AlveoloId) REFERENCES dbo.ALV (Id),
        CONSTRAINT FK_SL_MissaoLinha FOREIGN KEY (MissaoLinhaId) REFERENCES dbo.MissaoLinhas (Id),
        CONSTRAINT CK_SL_Quantidade CHECK (Quantidade > 0)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_SL_Sku_Alveolo' AND object_id = OBJECT_ID(N'dbo.SL'))
    CREATE INDEX IX_SL_Sku_Alveolo ON dbo.SL (Sku, AlveoloId);
GO

-------------------------------------------------------------------------
-- 19. SA — Stock por Armazém e Alvéolo
--     Quantidade atual por artigo e alvéolo — a "fotografia" que o
--     SL (18) vai atualizando ao longo do tempo.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'SA' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.SA
    (
        Sku            NVARCHAR(50)  NOT NULL,
        AlveoloId      NVARCHAR(50)  NOT NULL,
        Quantidade     INT           NOT NULL DEFAULT (0),
        AtualizadoEm   DATETIME2     NOT NULL DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_SA PRIMARY KEY (Sku, AlveoloId),
        CONSTRAINT FK_SA_Alveolo FOREIGN KEY (AlveoloId) REFERENCES dbo.ALV (Id),
        CONSTRAINT CK_SA_Quantidade CHECK (Quantidade >= 0)
    );
END
GO

-------------------------------------------------------------------------
-- 20. Seed — dados de exemplo. Cobre o circuito completo: Artigo ->
--     Ordem de Preparação (já composta, como chegaria de outro
--     software) -> Plataforma -> Missão, para que a PoC
--     controller/picking tenha algo real para trabalhar assim que a
--     base de dados for criada.
-------------------------------------------------------------------------

MERGE dbo.Zonas AS alvo
USING (VALUES
    (N'zona-a', N'A',      N'Picking geral'),
    (N'zona-b', N'B',      N'Volumosos'),
    (N'zona-c', N'C',      N'Frio'),
    (N'doca-1', N'Doca 1', N'Expedição')
) AS novo (Id, Codigo, Nome)
ON alvo.Id = novo.Id
WHEN MATCHED THEN
    UPDATE SET Codigo = novo.Codigo, Nome = novo.Nome
WHEN NOT MATCHED THEN
    INSERT (Id, Codigo, Nome) VALUES (novo.Id, novo.Codigo, novo.Nome);
GO

MERGE dbo.Modulos AS alvo
USING (VALUES
    (N'picking',       N'Picking',       CAST(1 AS BIT)),
    (N'transporte',     N'Transporte',     CAST(0 AS BIT)),
    (N'abastecimento',  N'Abastecimento',  CAST(0 AS BIT))
) AS novo (Slug, Nome, Disponivel)
ON alvo.Slug = novo.Slug
WHEN NOT MATCHED THEN
    INSERT (Slug, Nome, Disponivel) VALUES (novo.Slug, novo.Nome, novo.Disponivel);
GO

MERGE dbo.TER AS alvo
USING (VALUES
    (N'ter-001', N'PDA-001', N'Terminal de exemplo para a PoC')
) AS novo (Id, Codigo, Descricao)
ON alvo.Id = novo.Id
WHEN NOT MATCHED THEN
    INSERT (Id, Codigo, Descricao) VALUES (novo.Id, novo.Codigo, novo.Descricao);
GO

MERGE dbo.US AS alvo
USING (VALUES
    (N'us-001', N'42', N'1234', N'Operador de exemplo')
) AS novo (Id, NumeroOperador, Pin, Nome)
ON alvo.Id = novo.Id
WHEN NOT MATCHED THEN
    INSERT (Id, NumeroOperador, Pin, Nome) VALUES (novo.Id, novo.NumeroOperador, novo.Pin, novo.Nome);
GO

MERGE dbo.ALV AS alvo
USING (VALUES
    (N'alv-a0103', N'A-01-03', N'zona-a'),
    (N'alv-a0211', N'A-02-11', N'zona-a'),
    (N'alv-b0402', N'B-04-02', N'zona-b')
) AS novo (Id, Codigo, ZonaId)
ON alvo.Id = novo.Id
WHEN NOT MATCHED THEN
    INSERT (Id, Codigo, ZonaId) VALUES (novo.Id, novo.Codigo, novo.ZonaId);
GO

-- Dimensões de exemplo (mm) — por confirmar com o cliente.
MERGE dbo.CESTOS AS alvo
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
MERGE dbo.TiposPlataforma AS alvo
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

MERGE dbo.CM AS alvo
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

IF NOT EXISTS (SELECT 1 FROM dbo.RegrasMissao WHERE Chave = N'default')
BEGIN
    INSERT INTO dbo.RegrasMissao (Chave, MaxLinhasPorMissao, MaxPlataformasPorMissao, CriterioAgrupamento, CriterioOrdenacao)
    VALUES (N'default', 20, 4, N'Zona', N'Localizacao');
END
GO

-- Artigos de exemplo (dados mestre — RF-ENT-03). Dimensões da caixa em
-- cm; usadas pela cubicagem (Anexo A.1) para tipificar a ordem que os
-- reúne. Valores ilustrativos, não confirmados com o cliente.
MERGE dbo.Artigos AS alvo
USING (VALUES
    (N'SKU-1001', N'5601234567890', N'Parafuso M6x20 (caixa 100un)',  100, 30.0, 20.0, 15.0, 4.500, N'Pesado', 40),
    (N'SKU-2044', N'5601234500021', N'Luvas de proteção tamanho L',    50, 40.0, 30.0, 25.0, 3.000, N'Leve',   20),
    (N'SKU-3390', N'5601234511119', N'Fita adesiva 48mm',              24, 25.0, 25.0, 20.0, 2.200, N'Leve',   30)
) AS novo (Sku, Ean, Descricao, UnidadesPorCaixa, ComprimentoCaixaCm, LarguraCaixaCm, AlturaCaixaCm, PesoUnitarioKg, ClasseEmpilhamento, CaixasPorPaleteCompleta)
ON alvo.Sku = novo.Sku
WHEN MATCHED THEN
    UPDATE SET Ean = novo.Ean, Descricao = novo.Descricao, UnidadesPorCaixa = novo.UnidadesPorCaixa,
        ComprimentoCaixaCm = novo.ComprimentoCaixaCm, LarguraCaixaCm = novo.LarguraCaixaCm, AlturaCaixaCm = novo.AlturaCaixaCm,
        PesoUnitarioKg = novo.PesoUnitarioKg, ClasseEmpilhamento = novo.ClasseEmpilhamento, CaixasPorPaleteCompleta = novo.CaixasPorPaleteCompleta
WHEN NOT MATCHED THEN
    INSERT (Sku, Ean, Descricao, UnidadesPorCaixa, ComprimentoCaixaCm, LarguraCaixaCm, AlturaCaixaCm, PesoUnitarioKg, ClasseEmpilhamento, CaixasPorPaleteCompleta)
    VALUES (novo.Sku, novo.Ean, novo.Descricao, novo.UnidadesPorCaixa, novo.ComprimentoCaixaCm, novo.LarguraCaixaCm, novo.AlturaCaixaCm, novo.PesoUnitarioKg, novo.ClasseEmpilhamento, novo.CaixasPorPaleteCompleta);
GO

-- Stock de exemplo por alvéolo (SA) — RF-PIC: o operador escolhe o
-- alvéolo onde está de entre os que têm stock do artigo, na zona onde
-- se encontra (ver PickingEndpoints, endpoint /alveolos). SKU-1001 tem
-- stock em dois alvéolos da mesma zona (zona-a) de propósito, para o
-- ecrã mostrar mesmo uma escolha real. Sem WHEN MATCHED/UPDATE (ao
-- contrário dos MERGE acima): isto é dado "vivo" que o próprio picking
-- vai decrementando (como Plataformas/MISSAO mais abaixo) — corrida
-- outra vez, não pode repor o stock ao valor inicial por cima do que
-- já foi picado.
IF NOT EXISTS (SELECT 1 FROM dbo.SA WHERE Sku = N'SKU-1001' AND AlveoloId = N'alv-a0103')
    INSERT INTO dbo.SA (Sku, AlveoloId, Quantidade) VALUES (N'SKU-1001', N'alv-a0103', 15);
IF NOT EXISTS (SELECT 1 FROM dbo.SA WHERE Sku = N'SKU-1001' AND AlveoloId = N'alv-a0211')
    INSERT INTO dbo.SA (Sku, AlveoloId, Quantidade) VALUES (N'SKU-1001', N'alv-a0211', 5);
IF NOT EXISTS (SELECT 1 FROM dbo.SA WHERE Sku = N'SKU-2044' AND AlveoloId = N'alv-a0211')
    INSERT INTO dbo.SA (Sku, AlveoloId, Quantidade) VALUES (N'SKU-2044', N'alv-a0211', 10);
IF NOT EXISTS (SELECT 1 FROM dbo.SA WHERE Sku = N'SKU-3390' AND AlveoloId = N'alv-b0402')
    INSERT INTO dbo.SA (Sku, AlveoloId, Quantidade) VALUES (N'SKU-3390', N'alv-b0402', 12);
GO

-- Ordem de preparação de exemplo — simula o que chegaria já composta
-- de outro software (cliente/data/morada e os PS que a compõem já
-- decididos lá), tipificada e despachada, com a plataforma e a missão
-- de picking correspondentes — para que o `pda` tenha sempre uma
-- missão real para executar assim que a BD é criada.
IF NOT EXISTS (SELECT 1 FROM dbo.OrdensPreparacao WHERE Id = N'op-0001')
BEGIN
    INSERT INTO dbo.OrdensPreparacao (Id, Cliente, DataEntrega, MoradaEntrega, Estado, AlturaPaleteCm)
    VALUES (N'op-0001', N'Cliente de exemplo, Lda.', DATEADD(DAY, 2, CAST(SYSUTCDATETIME() AS DATE)), N'Rua Exemplo 123, Porto', N'Despachada', 140);
END
GO

IF NOT EXISTS (SELECT 1 FROM dbo.OrdensSeparacao WHERE Id = N'ps-0001')
BEGIN
    INSERT INTO dbo.OrdensSeparacao (Id, OrdemPreparacaoId, NumeroDocumento, Origem, Canal)
    VALUES (N'ps-0001', N'op-0001', N'PS-2026-0001', N'PHC', N'B2B');
END
GO

MERGE dbo.OrdensSeparacaoLinhas AS alvo
USING (VALUES
    (N'ps-linha-1', N'ps-0001', N'SKU-1001', 3, N'alv-a0103'),
    (N'ps-linha-2', N'ps-0001', N'SKU-2044', 2, N'alv-a0211'),
    (N'ps-linha-3', N'ps-0001', N'SKU-3390', 5, N'alv-b0402')
) AS novo (Id, OrdemSeparacaoId, Sku, Quantidade, AlveoloId)
ON alvo.Id = novo.Id
WHEN NOT MATCHED THEN
    INSERT (Id, OrdemSeparacaoId, Sku, Quantidade, AlveoloId)
    VALUES (novo.Id, novo.OrdemSeparacaoId, novo.Sku, novo.Quantidade, novo.AlveoloId);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Plataformas WHERE Id = N'plat-0001')
BEGIN
    INSERT INTO dbo.Plataformas (Id, Codigo, OrdemPreparacaoId, TipoPlataformaCodigo, IndiceCamada, ClasseCamada, Estado)
    VALUES (N'plat-0001', N'PLT-0001', N'op-0001', N'P2', 1, N'Leve', N'EmPicking');
END
GO

MERGE dbo.MISSAO AS alvo
USING (VALUES
    (N'missao-m0142', N'M-0142', N'Picking', N'zona-a', N'plat-0001', N'us-001', N'ter-001', N'Atribuida')
) AS novo (Id, Codigo, CentroTrabalho, ZonaId, PlataformaId, UtilizadorId, TerminalId, Estado)
ON alvo.Id = novo.Id
WHEN NOT MATCHED THEN
    INSERT (Id, Codigo, CentroTrabalho, ZonaId, PlataformaId, UtilizadorId, TerminalId, Estado, AtribuidaEm)
    VALUES (novo.Id, novo.Codigo, novo.CentroTrabalho, novo.ZonaId, novo.PlataformaId, novo.UtilizadorId, novo.TerminalId, novo.Estado, SYSUTCDATETIME());
GO

MERGE dbo.MissaoLinhas AS alvo
USING (VALUES
    (N'task-1', N'missao-m0142', N'SKU-1001', N'Parafuso M6x20 (caixa 100un)',  N'5601234567890', N'alv-a0103', N'PLT-0001', N'P2', 3),
    (N'task-2', N'missao-m0142', N'SKU-2044', N'Luvas de proteção tamanho L',   N'5601234500021', N'alv-a0211', N'PLT-0001', N'P2', 2),
    (N'task-3', N'missao-m0142', N'SKU-3390', N'Fita adesiva 48mm',             N'5601234511119', N'alv-b0402', N'PLT-0001', N'P2', 5)
) AS novo (Id, MissaoId, Sku, Descricao, CodigoBarras, AlveoloId, Plataforma, TipoPlataformaCodigo, QuantidadeAlvo)
ON alvo.Id = novo.Id
WHEN MATCHED THEN
    UPDATE SET Descricao = novo.Descricao, CodigoBarras = novo.CodigoBarras
WHEN NOT MATCHED THEN
    INSERT (Id, MissaoId, Sku, Descricao, CodigoBarras, AlveoloId, Plataforma, TipoPlataformaCodigo, QuantidadeAlvo)
    VALUES (novo.Id, novo.MissaoId, novo.Sku, novo.Descricao, novo.CodigoBarras, novo.AlveoloId, novo.Plataforma, novo.TipoPlataformaCodigo, novo.QuantidadeAlvo);
GO

PRINT 'Base de dados WOPA pronta.';
GO
