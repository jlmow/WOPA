/*
    WOPA — reset da base de dados (Microsoft SQL Server)
    =====================================================

    Apaga TODAS as tabelas do WOPA (estrutura + dados) para arrancar
    limpo antes de carregar dados reais. Script separado de propósito:
    schema.sql é seguro para correr a qualquer momento (idempotente,
    nunca destrutivo — ver o cabeçalho desse ficheiro); isto aqui é o
    oposto, só corre quando é mesmo intenção apagar tudo.

    Ordem de DROP pensada para respeitar as foreign keys (filhas antes
    das tabelas que referenciam) — ver ARCHITECTURE.md ADR-031.

    Como correr (e depois recriar do zero):
      sqlcmd -S <servidor> -d WOPA -E -f 65001 -i reset-database.sql
      sqlcmd -S <servidor> -d WOPA -E -f 65001 -i schema.sql

    Os nomes aqui são os que existiam antes do ADR-031 (maiúsculas/
    mistas) — como a colação por omissão do SQL Server é
    case-insensitive, DROP TABLE dbo.ALV e DROP TABLE dbo.alv acertam
    na mesma tabela; escritos como estavam só para ficar claro o que
    está mesmo a ser apagado.
*/

SET NOCOUNT ON;
GO

-- 1) Tabelas sem nada a depender delas.
DROP TABLE IF EXISTS dbo.Modulos;
DROP TABLE IF EXISTS dbo.Artigos;
DROP TABLE IF EXISTS dbo.RegrasMissao;
DROP TABLE IF EXISTS dbo.OrdensSeparacaoLinhas;
DROP TABLE IF EXISTS dbo.OperacoesProcessadas;
DROP TABLE IF EXISTS dbo.SL;
DROP TABLE IF EXISTS dbo.SA;
DROP TABLE IF EXISTS dbo.PlataformaCestos;
DROP TABLE IF EXISTS dbo.CestoInstancias;
GO

-- 2) Ficam sem dependentes depois do passo 1.
DROP TABLE IF EXISTS dbo.CM;
DROP TABLE IF EXISTS dbo.OrdensSeparacao;
DROP TABLE IF EXISTS dbo.MissaoLinhas;
GO

-- 3) Ficam sem dependentes depois do passo 2.
DROP TABLE IF EXISTS dbo.ALV;
DROP TABLE IF EXISTS dbo.CESTOS;
DROP TABLE IF EXISTS dbo.MISSAO;
GO

-- 4) Ficam sem dependentes depois do passo 3.
DROP TABLE IF EXISTS dbo.Plataformas;
DROP TABLE IF EXISTS dbo.Zonas;
DROP TABLE IF EXISTS dbo.TER;
DROP TABLE IF EXISTS dbo.US;
DROP TABLE IF EXISTS dbo.Celulas;
GO

-- 5) Só ficam sem dependentes no fim.
DROP TABLE IF EXISTS dbo.TiposPlataforma;
DROP TABLE IF EXISTS dbo.OrdensPreparacao;
GO

PRINT 'Base de dados WOPA apagada -- correr schema.sql a seguir para recriar (vazia, sem exemplos).';
GO
