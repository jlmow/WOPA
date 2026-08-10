/*
    WOPA — script de criação da base de dados (Microsoft SQL Server)
    ================================================================

    Cria a base de dados "WOPA" e o esquema descrito em ARCHITECTURE.md
    (ADR-003: uma base de dados, um schema por módulo). Cobre o que já
    está desenhado/validado na PoC do orchestrator + pda/picking:
    zonas, módulos, regras de missão configuráveis, missões e as suas
    linhas, e o registo de idempotência das operações offline (ADR-007).

    Como correr:
      sqlcmd -S <servidor> -E -i schema.sql
    ou abrir no SQL Server Management Studio / Azure Data Studio e
    executar (F5).

    Seguro para voltar a correr: cada CREATE está guardado por um
    IF NOT EXISTS, e o seed usa MERGE / verificação de existência, por
    isso não duplica dados se o script for executado mais que uma vez.

    NOTA: este script ainda não está ligado ao orchestrator — a app
    continua a correr com dados em memória durante a fase de PoC. É o
    schema-alvo para quando ligarmos o orchestrator a esta base de
    dados a sério (via EF Core ou Dapper).
*/

SET NOCOUNT ON;
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
-- 2. Schemas — um por módulo (ADR-003)
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'orchestrator')
    EXEC('CREATE SCHEMA orchestrator');
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'picking')
    EXEC('CREATE SCHEMA picking');
GO

-------------------------------------------------------------------------
-- 3. orchestrator.Zonas
--    Zonas do armazém (GET /api/zonas).
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'Zonas' AND schema_id = SCHEMA_ID(N'orchestrator'))
BEGIN
    CREATE TABLE orchestrator.Zonas
    (
        Id      NVARCHAR(50)  NOT NULL PRIMARY KEY,
        Codigo  NVARCHAR(20)  NOT NULL,
        Nome    NVARCHAR(100) NOT NULL
    );
END
GO

-------------------------------------------------------------------------
-- 4. orchestrator.Modulos
--    Módulos disponíveis no pda (GET /api/modulos).
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'Modulos' AND schema_id = SCHEMA_ID(N'orchestrator'))
BEGIN
    CREATE TABLE orchestrator.Modulos
    (
        Slug        NVARCHAR(50)  NOT NULL PRIMARY KEY,
        Nome        NVARCHAR(100) NOT NULL,
        Disponivel  BIT           NOT NULL DEFAULT (0)
    );
END
GO

-------------------------------------------------------------------------
-- 5. orchestrator.RegrasMissao
--    Regras de negócio para o controller criar missões — configuráveis
--    (destino final: editável a partir do core-config). Conjunto
--    básico proposto; o cliente vai validar/ajustar (ADR-010).
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'RegrasMissao' AND schema_id = SCHEMA_ID(N'orchestrator'))
BEGIN
    CREATE TABLE orchestrator.RegrasMissao
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
-- 6. orchestrator.OrdensPreparacao
--    Estrutura PROVISÓRIA — staging do que chega do PHC/OrdersHub
--    (ADR-008). Os campos exatos ficam por confirmar até sabermos qual
--    dos dois sistemas é consultado e como (consulta direta à BD, API,
--    exportação). Serve para já para ter o conceito no schema.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'OrdensPreparacao' AND schema_id = SCHEMA_ID(N'orchestrator'))
BEGIN
    CREATE TABLE orchestrator.OrdensPreparacao
    (
        Id                NVARCHAR(50)  NOT NULL PRIMARY KEY,
        NumeroDocumento   NVARCHAR(50)  NOT NULL,
        -- PHC | OrdersHub
        Origem            NVARCHAR(20)  NOT NULL,
        RecebidoEm        DATETIME2     NOT NULL DEFAULT (SYSUTCDATETIME()),
        Processada        BIT           NOT NULL DEFAULT (0),
        MissaoId          NVARCHAR(50)  NULL
    );
END
GO

-------------------------------------------------------------------------
-- 7. picking.Missoes
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'Missoes' AND schema_id = SCHEMA_ID(N'picking'))
BEGIN
    CREATE TABLE picking.Missoes
    (
        Id              NVARCHAR(50)  NOT NULL PRIMARY KEY,
        Codigo          NVARCHAR(30)  NOT NULL,
        ZonaId          NVARCHAR(50)  NULL,
        OperadorAtual   NVARCHAR(50)  NULL,
        -- Pendente | EmProgresso | Concluida
        Estado          NVARCHAR(20)  NOT NULL DEFAULT (N'Pendente'),
        CriadaEm        DATETIME2     NOT NULL DEFAULT (SYSUTCDATETIME()),
        ConcluidaEm     DATETIME2     NULL,

        CONSTRAINT FK_Missoes_Zona FOREIGN KEY (ZonaId) REFERENCES orchestrator.Zonas (Id)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_OrdensPreparacao_Missao')
BEGIN
    ALTER TABLE orchestrator.OrdensPreparacao
        ADD CONSTRAINT FK_OrdensPreparacao_Missao FOREIGN KEY (MissaoId) REFERENCES picking.Missoes (Id);
END
GO

-------------------------------------------------------------------------
-- 8. picking.MissaoLinhas
--    Uma linha por artigo a picar dentro de uma missão (o que a PoC
--    chama "PickingTask"). Corresponde a GET /api/picking/tasks.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'MissaoLinhas' AND schema_id = SCHEMA_ID(N'picking'))
BEGIN
    CREATE TABLE picking.MissaoLinhas
    (
        Id                NVARCHAR(50)   NOT NULL PRIMARY KEY,
        MissaoId          NVARCHAR(50)   NOT NULL,
        Sku               NVARCHAR(50)   NOT NULL,
        Descricao         NVARCHAR(200)  NOT NULL,
        CodigoBarras      NVARCHAR(50)   NOT NULL,
        Localizacao       NVARCHAR(30)   NOT NULL,
        Plataforma        NVARCHAR(30)   NOT NULL,
        QuantidadeAlvo    INT            NOT NULL,
        QuantidadeLida    INT            NOT NULL DEFAULT (0),
        -- Pendente | EmProgresso | Concluida
        Estado            NVARCHAR(20)   NOT NULL DEFAULT (N'Pendente'),

        CONSTRAINT FK_MissaoLinhas_Missao FOREIGN KEY (MissaoId) REFERENCES picking.Missoes (Id),
        CONSTRAINT CK_MissaoLinhas_Quantidade CHECK (QuantidadeLida >= 0 AND QuantidadeLida <= QuantidadeAlvo)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_MissaoLinhas_MissaoId' AND object_id = OBJECT_ID(N'picking.MissaoLinhas'))
BEGIN
    CREATE INDEX IX_MissaoLinhas_MissaoId ON picking.MissaoLinhas (MissaoId);
END
GO

-------------------------------------------------------------------------
-- 9. picking.OperacoesProcessadas
--    Idempotência das operações vindas de PDAs offline (ADR-007):
--    guarda o operacaoId gerado no dispositivo para não duplicar o
--    efeito de um reenvio.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'OperacoesProcessadas' AND schema_id = SCHEMA_ID(N'picking'))
BEGIN
    CREATE TABLE picking.OperacoesProcessadas
    (
        OperacaoId      NVARCHAR(50)  NOT NULL PRIMARY KEY,
        MissaoLinhaId   NVARCHAR(50)  NOT NULL,
        -- scan | confirm
        Tipo            NVARCHAR(20)  NOT NULL,
        ProcessadoEm    DATETIME2     NOT NULL DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT FK_OperacoesProcessadas_Linha FOREIGN KEY (MissaoLinhaId) REFERENCES picking.MissaoLinhas (Id)
    );
END
GO

-------------------------------------------------------------------------
-- 10. Seed — mesmos dados de exemplo já usados na PoC do orchestrator,
--     para que o comportamento seja idêntico assim que a app for ligada
--     a esta base de dados.
-------------------------------------------------------------------------

MERGE orchestrator.Zonas AS alvo
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

MERGE orchestrator.Modulos AS alvo
USING (VALUES
    (N'picking',       N'Picking',       CAST(1 AS BIT)),
    (N'transporte',     N'Transporte',     CAST(0 AS BIT)),
    (N'abastecimento',  N'Abastecimento',  CAST(0 AS BIT))
) AS novo (Slug, Nome, Disponivel)
ON alvo.Slug = novo.Slug
WHEN NOT MATCHED THEN
    INSERT (Slug, Nome, Disponivel) VALUES (novo.Slug, novo.Nome, novo.Disponivel);
GO

IF NOT EXISTS (SELECT 1 FROM orchestrator.RegrasMissao WHERE Chave = N'default')
BEGIN
    INSERT INTO orchestrator.RegrasMissao (Chave, MaxLinhasPorMissao, MaxPlataformasPorMissao, CriterioAgrupamento, CriterioOrdenacao)
    VALUES (N'default', 20, 4, N'Zona', N'Localizacao');
END
GO

MERGE picking.Missoes AS alvo
USING (VALUES
    (N'missao-m0142', N'M-0142', N'zona-a', N'Pendente')
) AS novo (Id, Codigo, ZonaId, Estado)
ON alvo.Id = novo.Id
WHEN NOT MATCHED THEN
    INSERT (Id, Codigo, ZonaId, Estado) VALUES (novo.Id, novo.Codigo, novo.ZonaId, novo.Estado);
GO

MERGE picking.MissaoLinhas AS alvo
USING (VALUES
    (N'task-1', N'missao-m0142', N'SKU-1001', N'Parafuso M6x20 (caixa 100un)',  N'5601234567890', N'A-01-03', N'P-01', 3),
    (N'task-2', N'missao-m0142', N'SKU-2044', N'Luvas de proteção tamanho L',   N'5601234500021', N'A-02-11', N'P-01', 2),
    (N'task-3', N'missao-m0142', N'SKU-3390', N'Fita adesiva 48mm',             N'5601234511119', N'B-04-02', N'P-02', 5)
) AS novo (Id, MissaoId, Sku, Descricao, CodigoBarras, Localizacao, Plataforma, QuantidadeAlvo)
ON alvo.Id = novo.Id
WHEN NOT MATCHED THEN
    INSERT (Id, MissaoId, Sku, Descricao, CodigoBarras, Localizacao, Plataforma, QuantidadeAlvo)
    VALUES (novo.Id, novo.MissaoId, novo.Sku, novo.Descricao, novo.CodigoBarras, novo.Localizacao, novo.Plataforma, novo.QuantidadeAlvo);
GO

PRINT 'Base de dados WOPA pronta.';
GO
