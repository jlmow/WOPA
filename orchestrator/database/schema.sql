/*
    WOPA — script de criação da base de dados (Microsoft SQL Server)
    ================================================================

    Cria a base de dados "WOPA" com todas as tabelas num único schema
    (dbo) — decisão do cliente: mais simples de gerir na prática do que
    separar por módulo, sobretudo havendo tabelas partilhadas entre
    aplicações (ver ADR-003, atualizado). Cobre o modelo de dados real
    de armazém: terminais, utilizadores, alvéolos, cestos, tipos de
    plataforma, movimentos e stock, e a receção de Ordens de Separação
    (ADR-008/011).

    Como correr:
      sqlcmd -S <servidor> -E -i schema.sql
    ou abrir no SQL Server Management Studio / Azure Data Studio e
    executar (F5).

    Seguro para voltar a correr: cada CREATE está guardado por um
    IF NOT EXISTS, e o seed usa MERGE / verificação de existência, por
    isso não duplica dados se o script for executado mais que uma vez.

    NOTA: este script é o schema-alvo; o `orchestrator` já liga a ele a
    sério via EF Core (ver ARCHITECTURE.md ADR-012) — validado contra
    uma instância real (Docker, só para desenvolvimento/teste). Ainda
    falta a connection string do servidor real do cliente para
    produção.

    Convenção de nomes: TER, US, ALV, CESTOS, MISSAO, SL, SA e CM são
    nomes de tabela pedidos explicitamente pelo cliente (não apenas
    códigos de referência) — mantidos exatamente assim. As restantes
    tabelas usam nomes descritivos por não terem código pedido.
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
-- 8. TiposPlataforma
--    P0 (palete completa), P1/P2/P4 (palete + 1/2/4 cestos) —
--    dimensões e altura.
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
        CestosPorPlataforma   INT           NOT NULL DEFAULT (0)   -- 0 para P0 (palete completa, sem cestos)
    );
END
GO

-------------------------------------------------------------------------
-- 9. CM — Código de Movimentos de Stock
--    Regra do cliente: CM_ID < 500 é entrada de stock,
--    CM_ID > 500 é saída — refletida diretamente numa coluna
--    calculada, para não depender de aplicações externas acertarem a
--    regra sempre da mesma forma. (CM_ID = 500 fica indefinido de
--    propósito — evitar usar esse valor.)
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
-- 10. RegrasMissao (ADR-010)
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
-- 11. OrdensSeparacao + OrdensSeparacaoLinhas
--     Independentemente da origem (PHC ou OrdersHub), a informação é
--     escrita aqui através de POST /api/ordens-separacao — é a partir
--     desta tabela que o trabalho do controller começa (ADR-011).
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'OrdensSeparacao' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.OrdensSeparacao
    (
        Id                NVARCHAR(50)  NOT NULL PRIMARY KEY,
        NumeroDocumento   NVARCHAR(50)  NOT NULL,
        -- PHC | OrdersHub | ... (a confirmar — ADR-008)
        Origem            NVARCHAR(20)  NOT NULL,
        RecebidaEm        DATETIME2     NOT NULL DEFAULT (SYSUTCDATETIME()),
        Processada        BIT           NOT NULL DEFAULT (0),
        MissaoId          NVARCHAR(50)  NULL
    );
END
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

        CONSTRAINT FK_OrdensSeparacaoLinhas_Ordem FOREIGN KEY (OrdemSeparacaoId) REFERENCES dbo.OrdensSeparacao (Id),
        CONSTRAINT FK_OrdensSeparacaoLinhas_Alveolo FOREIGN KEY (AlveoloId) REFERENCES dbo.ALV (Id),
        CONSTRAINT CK_OrdensSeparacaoLinhas_Quantidade CHECK (Quantidade > 0)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_OrdensSeparacaoLinhas_OrdemId' AND object_id = OBJECT_ID(N'dbo.OrdensSeparacaoLinhas'))
    CREATE INDEX IX_OrdensSeparacaoLinhas_OrdemId ON dbo.OrdensSeparacaoLinhas (OrdemSeparacaoId);
GO

-------------------------------------------------------------------------
-- 12. MISSAO
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'MISSAO' AND schema_id = SCHEMA_ID(N'dbo'))
BEGIN
    CREATE TABLE dbo.MISSAO
    (
        Id              NVARCHAR(50)  NOT NULL PRIMARY KEY,
        Codigo          NVARCHAR(30)  NOT NULL,
        ZonaId          NVARCHAR(50)  NULL,
        UtilizadorId    NVARCHAR(50)  NULL,   -- operador a quem a missão está atribuída
        TerminalId      NVARCHAR(50)  NULL,   -- PDA que a está a executar
        -- Pendente | EmProgresso | Concluida
        Estado          NVARCHAR(20)  NOT NULL DEFAULT (N'Pendente'),
        CriadaEm        DATETIME2     NOT NULL DEFAULT (SYSUTCDATETIME()),
        ConcluidaEm     DATETIME2     NULL,

        CONSTRAINT FK_MISSAO_Zona FOREIGN KEY (ZonaId) REFERENCES dbo.Zonas (Id),
        CONSTRAINT FK_MISSAO_Utilizador FOREIGN KEY (UtilizadorId) REFERENCES dbo.US (Id),
        CONSTRAINT FK_MISSAO_Terminal FOREIGN KEY (TerminalId) REFERENCES dbo.TER (Id)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_OrdensSeparacao_Missao')
BEGIN
    ALTER TABLE dbo.OrdensSeparacao
        ADD CONSTRAINT FK_OrdensSeparacao_Missao FOREIGN KEY (MissaoId) REFERENCES dbo.MISSAO (Id);
END
GO

-------------------------------------------------------------------------
-- 13. MissaoLinhas
--     Uma linha por artigo a picar dentro de uma missão. Corresponde a
--     GET /api/picking/tasks — agora com alvéolo, tipo de plataforma e
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
-- 14. OperacoesProcessadas
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
-- 15. SL — Movimentos de Stock
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
-- 16. SA — Stock por Armazém e Alvéolo
--     Quantidade atual por artigo e alvéolo — a "fotografia" que o
--     SL (15) vai atualizando ao longo do tempo.
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
-- 17. Seed — mesmos dados de exemplo já usados na PoC do orchestrator,
--     para que o comportamento seja idêntico assim que a app for ligada
--     a esta base de dados.
-------------------------------------------------------------------------

MERGE dbo.Zonas AS alvo
USING (VALUES
    (N'zona-a', N'A',      N'Picking geral'),
    (N'zona-b', N'B',      N'Volumosos'),
    (N'zona-c', N'C',      N'Frio'),
    (N'doca-1', N'Doca 1', N'Expedição')
) AS novo (Id, Codigo, Nome)
ON alvo.Id = novo.Id
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

-- Dimensões de exemplo (mm, base de palete EUR 1200x800) — por confirmar.
MERGE dbo.TiposPlataforma AS alvo
USING (VALUES
    (N'P0', N'Palete completa',    1200, 800, 1800, 0),
    (N'P1', N'Palete + 1 cesto',   1200, 800, 1800, 1),
    (N'P2', N'Palete + 2 cestos',  1200, 800, 1800, 2),
    (N'P4', N'Palete + 4 cestos',  1200, 800, 1800, 4)
) AS novo (Codigo, Descricao, ComprimentoMm, LarguraMm, AlturaMm, CestosPorPlataforma)
ON alvo.Codigo = novo.Codigo
WHEN NOT MATCHED THEN
    INSERT (Codigo, Descricao, ComprimentoMm, LarguraMm, AlturaMm, CestosPorPlataforma)
    VALUES (novo.Codigo, novo.Descricao, novo.ComprimentoMm, novo.LarguraMm, novo.AlturaMm, novo.CestosPorPlataforma);
GO

MERGE dbo.CM AS alvo
USING (VALUES
    (100, N'Entrada por compra'),
    (110, N'Entrada por devolução de cliente'),
    (501, N'Saída por picking'),
    (510, N'Saída por quebra')
) AS novo (Id, Descricao)
ON alvo.Id = novo.Id
WHEN NOT MATCHED THEN
    INSERT (Id, Descricao) VALUES (novo.Id, novo.Descricao);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.RegrasMissao WHERE Chave = N'default')
BEGIN
    INSERT INTO dbo.RegrasMissao (Chave, MaxLinhasPorMissao, MaxPlataformasPorMissao, CriterioAgrupamento, CriterioOrdenacao)
    VALUES (N'default', 20, 4, N'Zona', N'Localizacao');
END
GO

MERGE dbo.MISSAO AS alvo
USING (VALUES
    (N'missao-m0142', N'M-0142', N'zona-a', N'us-001', N'ter-001', N'Pendente')
) AS novo (Id, Codigo, ZonaId, UtilizadorId, TerminalId, Estado)
ON alvo.Id = novo.Id
WHEN NOT MATCHED THEN
    INSERT (Id, Codigo, ZonaId, UtilizadorId, TerminalId, Estado)
    VALUES (novo.Id, novo.Codigo, novo.ZonaId, novo.UtilizadorId, novo.TerminalId, novo.Estado);
GO

MERGE dbo.MissaoLinhas AS alvo
USING (VALUES
    (N'task-1', N'missao-m0142', N'SKU-1001', N'Parafuso M6x20 (caixa 100un)',  N'5601234567890', N'alv-a0103', N'P-01', N'P1', 3),
    (N'task-2', N'missao-m0142', N'SKU-2044', N'Luvas de proteção tamanho L',   N'5601234500021', N'alv-a0211', N'P-01', N'P1', 2),
    (N'task-3', N'missao-m0142', N'SKU-3390', N'Fita adesiva 48mm',             N'5601234511119', N'alv-b0402', N'P-02', N'P2', 5)
) AS novo (Id, MissaoId, Sku, Descricao, CodigoBarras, AlveoloId, Plataforma, TipoPlataformaCodigo, QuantidadeAlvo)
ON alvo.Id = novo.Id
WHEN NOT MATCHED THEN
    INSERT (Id, MissaoId, Sku, Descricao, CodigoBarras, AlveoloId, Plataforma, TipoPlataformaCodigo, QuantidadeAlvo)
    VALUES (novo.Id, novo.MissaoId, novo.Sku, novo.Descricao, novo.CodigoBarras, novo.AlveoloId, novo.Plataforma, novo.TipoPlataformaCodigo, novo.QuantidadeAlvo);
GO

PRINT 'Base de dados WOPA pronta.';
GO
