/*
    WOPA — script de criação da base de dados (Microsoft SQL Server)
    ================================================================

    Cria a base de dados "WOPA" e o esquema descrito em ARCHITECTURE.md
    (ADR-003: uma base de dados, um schema por módulo), já com o modelo
    de dados real de armazém indicado pelo cliente: terminais,
    utilizadores, alvéolos, cestos, tipos de plataforma, movimentos e
    stock, e a receção de Ordens de Separação (ADR-008/011).

    Como correr:
      sqlcmd -S <servidor> -E -i schema.sql
    ou abrir no SQL Server Management Studio / Azure Data Studio e
    executar (F5).

    Seguro para voltar a correr: cada CREATE está guardado por um
    IF NOT EXISTS, e o seed usa MERGE / verificação de existência, por
    isso não duplica dados se o script for executado mais que uma vez.

    NOTA: este script ainda não está ligado ao orchestrator — a app
    continua a correr com dados em memória durante a fase de PoC
    (incluindo o novo endpoint de Ordens de Separação). É o schema-alvo
    para quando ligarmos o orchestrator a esta base de dados a sério
    (via EF Core ou Dapper). Também não foi executado contra uma
    instância real de SQL Server (nenhuma disponível no ambiente onde
    foi escrito) — confirmar antes de confiar nele em produção.

    Convenção de nomes: os códigos entre parêntesis nos comentários
    (TER, US, ALV, CESTOS, CM, SL, SA, ...) são os que o cliente usou
    ao descrever as tabelas — mantidos aqui como referência cruzada.
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
-- 5. orchestrator.Terminais (TER)
--    Um registo por PDA/dispositivo.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'Terminais' AND schema_id = SCHEMA_ID(N'orchestrator'))
BEGIN
    CREATE TABLE orchestrator.Terminais
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
-- 6. orchestrator.Utilizadores (US)
--    Operadores — hoje o pda só pede um "número de operador" no login
--    sem validar contra nada; esta tabela é o destino real dessa
--    validação (ver ARCHITECTURE.md secção 8).
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'Utilizadores' AND schema_id = SCHEMA_ID(N'orchestrator'))
BEGIN
    CREATE TABLE orchestrator.Utilizadores
    (
        Id                NVARCHAR(50)  NOT NULL PRIMARY KEY,   -- US_ID
        NumeroOperador    NVARCHAR(20)  NOT NULL UNIQUE,        -- US_Numero, o que se digita no pda
        Nome              NVARCHAR(100) NOT NULL,
        Ativo             BIT           NOT NULL DEFAULT (1)
    );
END
GO

-------------------------------------------------------------------------
-- 7. orchestrator.Alveolos (ALV)
--    Localização física dentro de uma zona — hoje a PoC guarda isto só
--    como texto livre em MissaoLinhas.Localizacao; esta tabela é a
--    referência própria para essa informação.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'Alveolos' AND schema_id = SCHEMA_ID(N'orchestrator'))
BEGIN
    CREATE TABLE orchestrator.Alveolos
    (
        Id        NVARCHAR(50)  NOT NULL PRIMARY KEY,   -- ALV_ID
        Codigo    NVARCHAR(30)  NOT NULL UNIQUE,         -- ALV_Codigo, ex. "A-01-03"
        ZonaId    NVARCHAR(50)  NOT NULL,
        Ativo     BIT           NOT NULL DEFAULT (1),

        CONSTRAINT FK_Alveolos_Zona FOREIGN KEY (ZonaId) REFERENCES orchestrator.Zonas (Id)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Alveolos_ZonaId' AND object_id = OBJECT_ID(N'orchestrator.Alveolos'))
    CREATE INDEX IX_Alveolos_ZonaId ON orchestrator.Alveolos (ZonaId);
GO

-------------------------------------------------------------------------
-- 8. orchestrator.Cestos (CESTOS)
--    Tipos de cesto: dimensões e quantos cabem numa palete.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'Cestos' AND schema_id = SCHEMA_ID(N'orchestrator'))
BEGIN
    CREATE TABLE orchestrator.Cestos
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
-- 9. orchestrator.TiposPlataforma
--    P0 (palete completa), P1/P2/P4 (palete + 1/2/4 cestos) —
--    dimensões e altura.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'TiposPlataforma' AND schema_id = SCHEMA_ID(N'orchestrator'))
BEGIN
    CREATE TABLE orchestrator.TiposPlataforma
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
-- 10. orchestrator.CodigosMovimento (CM)
--     Regra do cliente: CM_ID < 500 é entrada de stock,
--     CM_ID > 500 é saída — refletida diretamente numa coluna
--     calculada, para não depender de aplicações externas acertarem a
--     regra sempre da mesma forma. (CM_ID = 500 fica indefinido de
--     propósito — evitar usar esse valor.)
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'CodigosMovimento' AND schema_id = SCHEMA_ID(N'orchestrator'))
BEGIN
    CREATE TABLE orchestrator.CodigosMovimento
    (
        Id          INT           NOT NULL PRIMARY KEY,   -- CM_ID
        Descricao   NVARCHAR(100) NOT NULL,
        Tipo AS (CASE WHEN Id < 500 THEN N'Entrada' WHEN Id > 500 THEN N'Saida' ELSE N'Indefinido' END) PERSISTED
    );
END
GO

-------------------------------------------------------------------------
-- 11. orchestrator.RegrasMissao (ADR-010)
--     Regras de negócio para o controller criar missões — versão
--     básica proposta, ainda por validar com o cliente.
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
-- 12. orchestrator.OrdensSeparacao + OrdensSeparacaoLinhas
--     Independentemente da origem (PHC ou OrdersHub), a informação é
--     escrita aqui através de POST /api/ordens-separacao — é a partir
--     desta tabela que o trabalho do controller começa (ADR-011).
--     (O mesmo conceito foi chamado "Ordens de Preparação" numa
--     conversa anterior com o cliente — mantemos "Ordens de Separação"
--     como nome canónico a partir de agora.)
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'OrdensSeparacao' AND schema_id = SCHEMA_ID(N'orchestrator'))
BEGIN
    CREATE TABLE orchestrator.OrdensSeparacao
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

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'OrdensSeparacaoLinhas' AND schema_id = SCHEMA_ID(N'orchestrator'))
BEGIN
    CREATE TABLE orchestrator.OrdensSeparacaoLinhas
    (
        Id                  NVARCHAR(50)  NOT NULL PRIMARY KEY,
        OrdemSeparacaoId    NVARCHAR(50)  NOT NULL,
        Sku                 NVARCHAR(50)  NOT NULL,
        Quantidade          INT           NOT NULL,
        AlveoloId           NVARCHAR(50)  NULL,

        CONSTRAINT FK_OrdensSeparacaoLinhas_Ordem FOREIGN KEY (OrdemSeparacaoId) REFERENCES orchestrator.OrdensSeparacao (Id),
        CONSTRAINT FK_OrdensSeparacaoLinhas_Alveolo FOREIGN KEY (AlveoloId) REFERENCES orchestrator.Alveolos (Id),
        CONSTRAINT CK_OrdensSeparacaoLinhas_Quantidade CHECK (Quantidade > 0)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_OrdensSeparacaoLinhas_OrdemId' AND object_id = OBJECT_ID(N'orchestrator.OrdensSeparacaoLinhas'))
    CREATE INDEX IX_OrdensSeparacaoLinhas_OrdemId ON orchestrator.OrdensSeparacaoLinhas (OrdemSeparacaoId);
GO

-------------------------------------------------------------------------
-- 13. picking.Missoes
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'Missoes' AND schema_id = SCHEMA_ID(N'picking'))
BEGIN
    CREATE TABLE picking.Missoes
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

        CONSTRAINT FK_Missoes_Zona FOREIGN KEY (ZonaId) REFERENCES orchestrator.Zonas (Id),
        CONSTRAINT FK_Missoes_Utilizador FOREIGN KEY (UtilizadorId) REFERENCES orchestrator.Utilizadores (Id),
        CONSTRAINT FK_Missoes_Terminal FOREIGN KEY (TerminalId) REFERENCES orchestrator.Terminais (Id)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_OrdensSeparacao_Missao')
BEGIN
    ALTER TABLE orchestrator.OrdensSeparacao
        ADD CONSTRAINT FK_OrdensSeparacao_Missao FOREIGN KEY (MissaoId) REFERENCES picking.Missoes (Id);
END
GO

-------------------------------------------------------------------------
-- 14. picking.MissaoLinhas
--     Uma linha por artigo a picar dentro de uma missão. Corresponde a
--     GET /api/picking/tasks — agora com alvéolo, tipo de plataforma e
--     cestos necessários, em vez de localização em texto livre.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'MissaoLinhas' AND schema_id = SCHEMA_ID(N'picking'))
BEGIN
    CREATE TABLE picking.MissaoLinhas
    (
        Id                     NVARCHAR(50)   NOT NULL PRIMARY KEY,
        MissaoId               NVARCHAR(50)   NOT NULL,
        Sku                    NVARCHAR(50)   NOT NULL,   -- artigo
        Descricao              NVARCHAR(200)  NOT NULL,
        CodigoBarras           NVARCHAR(50)   NOT NULL,
        AlveoloId              NVARCHAR(50)   NOT NULL,   -- de onde se pica
        Plataforma             NVARCHAR(30)   NOT NULL,   -- identificador da palete/tote de destino desta missão
        TipoPlataformaCodigo   NVARCHAR(10)   NOT NULL,   -- P0 | P1 | P2 | P4
        CestoId                NVARCHAR(50)   NULL,
        CestosNecessarios      INT            NOT NULL DEFAULT (0),
        QuantidadeAlvo         INT            NOT NULL,
        QuantidadeLida         INT            NOT NULL DEFAULT (0),
        -- Pendente | EmProgresso | Concluida
        Estado                 NVARCHAR(20)   NOT NULL DEFAULT (N'Pendente'),

        CONSTRAINT FK_MissaoLinhas_Missao FOREIGN KEY (MissaoId) REFERENCES picking.Missoes (Id),
        CONSTRAINT FK_MissaoLinhas_Alveolo FOREIGN KEY (AlveoloId) REFERENCES orchestrator.Alveolos (Id),
        CONSTRAINT FK_MissaoLinhas_TipoPlataforma FOREIGN KEY (TipoPlataformaCodigo) REFERENCES orchestrator.TiposPlataforma (Codigo),
        CONSTRAINT FK_MissaoLinhas_Cesto FOREIGN KEY (CestoId) REFERENCES orchestrator.Cestos (Id),
        CONSTRAINT CK_MissaoLinhas_Quantidade CHECK (QuantidadeLida >= 0 AND QuantidadeLida <= QuantidadeAlvo)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_MissaoLinhas_MissaoId' AND object_id = OBJECT_ID(N'picking.MissaoLinhas'))
    CREATE INDEX IX_MissaoLinhas_MissaoId ON picking.MissaoLinhas (MissaoId);
GO

-------------------------------------------------------------------------
-- 15. picking.OperacoesProcessadas
--     Idempotência das operações vindas de PDAs offline (ADR-007).
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
-- 16. orchestrator.MovimentosStock (SL)
--     Ledger de movimentos — cada picking confirmado gera aqui um
--     movimento de saída (CM_ID > 500).
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'MovimentosStock' AND schema_id = SCHEMA_ID(N'orchestrator'))
BEGIN
    CREATE TABLE orchestrator.MovimentosStock
    (
        Id                  BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        CodigoMovimentoId   INT            NOT NULL,
        Sku                 NVARCHAR(50)   NOT NULL,
        AlveoloId           NVARCHAR(50)   NOT NULL,
        Quantidade          INT            NOT NULL,   -- sempre positivo; o sinal vem do CodigoMovimentoId
        MissaoLinhaId       NVARCHAR(50)   NULL,        -- preenchido quando o movimento vem de um picking
        CriadoEm            DATETIME2      NOT NULL DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT FK_MovimentosStock_Codigo FOREIGN KEY (CodigoMovimentoId) REFERENCES orchestrator.CodigosMovimento (Id),
        CONSTRAINT FK_MovimentosStock_Alveolo FOREIGN KEY (AlveoloId) REFERENCES orchestrator.Alveolos (Id),
        CONSTRAINT FK_MovimentosStock_MissaoLinha FOREIGN KEY (MissaoLinhaId) REFERENCES picking.MissaoLinhas (Id),
        CONSTRAINT CK_MovimentosStock_Quantidade CHECK (Quantidade > 0)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_MovimentosStock_Sku_Alveolo' AND object_id = OBJECT_ID(N'orchestrator.MovimentosStock'))
    CREATE INDEX IX_MovimentosStock_Sku_Alveolo ON orchestrator.MovimentosStock (Sku, AlveoloId);
GO

-------------------------------------------------------------------------
-- 17. orchestrator.StockArmazem (SA)
--     Quantidade atual por artigo e alvéolo — a "fotografia" que os
--     MovimentosStock (16) vão atualizando ao longo do tempo.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = N'StockArmazem' AND schema_id = SCHEMA_ID(N'orchestrator'))
BEGIN
    CREATE TABLE orchestrator.StockArmazem
    (
        Sku            NVARCHAR(50)  NOT NULL,
        AlveoloId      NVARCHAR(50)  NOT NULL,
        Quantidade     INT           NOT NULL DEFAULT (0),
        AtualizadoEm   DATETIME2     NOT NULL DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_StockArmazem PRIMARY KEY (Sku, AlveoloId),
        CONSTRAINT FK_StockArmazem_Alveolo FOREIGN KEY (AlveoloId) REFERENCES orchestrator.Alveolos (Id),
        CONSTRAINT CK_StockArmazem_Quantidade CHECK (Quantidade >= 0)
    );
END
GO

-------------------------------------------------------------------------
-- 18. Seed — mesmos dados de exemplo já usados na PoC do orchestrator,
--     estendidos com as novas tabelas, para que o comportamento seja
--     idêntico assim que a app for ligada a esta base de dados.
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

MERGE orchestrator.Terminais AS alvo
USING (VALUES
    (N'ter-001', N'PDA-001', N'Terminal de exemplo para a PoC')
) AS novo (Id, Codigo, Descricao)
ON alvo.Id = novo.Id
WHEN NOT MATCHED THEN
    INSERT (Id, Codigo, Descricao) VALUES (novo.Id, novo.Codigo, novo.Descricao);
GO

MERGE orchestrator.Utilizadores AS alvo
USING (VALUES
    (N'us-001', N'42', N'Operador de exemplo')
) AS novo (Id, NumeroOperador, Nome)
ON alvo.Id = novo.Id
WHEN NOT MATCHED THEN
    INSERT (Id, NumeroOperador, Nome) VALUES (novo.Id, novo.NumeroOperador, novo.Nome);
GO

MERGE orchestrator.Alveolos AS alvo
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
MERGE orchestrator.Cestos AS alvo
USING (VALUES
    (N'cesto-standard', N'CESTO-STD', 600, 400, 300, 4)
) AS novo (Id, Codigo, ComprimentoMm, LarguraMm, AlturaMm, QuantidadePorPalete)
ON alvo.Id = novo.Id
WHEN NOT MATCHED THEN
    INSERT (Id, Codigo, ComprimentoMm, LarguraMm, AlturaMm, QuantidadePorPalete)
    VALUES (novo.Id, novo.Codigo, novo.ComprimentoMm, novo.LarguraMm, novo.AlturaMm, novo.QuantidadePorPalete);
GO

-- Dimensões de exemplo (mm, base de palete EUR 1200x800) — por confirmar.
MERGE orchestrator.TiposPlataforma AS alvo
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

MERGE orchestrator.CodigosMovimento AS alvo
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

IF NOT EXISTS (SELECT 1 FROM orchestrator.RegrasMissao WHERE Chave = N'default')
BEGIN
    INSERT INTO orchestrator.RegrasMissao (Chave, MaxLinhasPorMissao, MaxPlataformasPorMissao, CriterioAgrupamento, CriterioOrdenacao)
    VALUES (N'default', 20, 4, N'Zona', N'Localizacao');
END
GO

MERGE picking.Missoes AS alvo
USING (VALUES
    (N'missao-m0142', N'M-0142', N'zona-a', N'us-001', N'ter-001', N'Pendente')
) AS novo (Id, Codigo, ZonaId, UtilizadorId, TerminalId, Estado)
ON alvo.Id = novo.Id
WHEN NOT MATCHED THEN
    INSERT (Id, Codigo, ZonaId, UtilizadorId, TerminalId, Estado)
    VALUES (novo.Id, novo.Codigo, novo.ZonaId, novo.UtilizadorId, novo.TerminalId, novo.Estado);
GO

MERGE picking.MissaoLinhas AS alvo
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
