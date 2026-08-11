/*
    WOPA — dados de teste para o primeiro teste real num terminal
    Android (leitura de código de barras)
    =====================================================================

    A Ordem de Preparação (cabeçalho) e as 4 linhas de PS são REAIS —
    amostra do PHC que o cliente partilhou: ordem 1113 / pedido 21628 /
    numpf 96123 ("número de proforma/encomenda", confirmado pelo
    cliente), "Glas In Loodbedrijf Van Dommelen BV", P2, 1 plataforma,
    4 referências. As 4 linhas (bostamp 5C53A611-2DC6-4F31-A726-...)
    batem certo com o cabeçalho: caixas_nec soma 18, vol_pick soma
    140280 cm³, peso_linha soma 27.78 kg — exatamente os totais dados.
    O código de barras de cada linha ("artigo") é um EAN-13 real
    (prefixo 560 = Portugal).

    Só o que o cliente ainda não enviou foi inventado: descrição de
    artigo, dimensões de caixa/peso unitário (o PHC só deu o total já
    calculado por linha, não a ficha do artigo em si), zona/alvéolos e
    stock. Isto não bloqueia o teste — a tipificação já vem decidida
    (ADR-032), a cubicagem do WOPA nem entra em jogo para esta Ordem.

    Todos os IDs de zona/alvéolo/plataforma/missão têm prefixo
    "teste"/"TST-" de propósito — fácil de identificar e de apagar mais
    tarde (ver fundo do ficheiro). Os SKUs usam o próprio código de
    barras real (não haver um código de artigo separado do EAN nesta
    amostra) prefixados com "TST-" só para ficarem fáceis de encontrar.

    Como correr (depois de reset-database.sql + schema.sql):
      sqlcmd -S <servidor> -d WOPA -E -f 65001 -i dados-teste.sql

    O que fica pronto para o pda:
      - 1 missão de picking (Zona de Teste A), plataforma P2 (2 cestos)
        ainda por montar — primeiro ecrã a aparecer é "Montar
        plataforma" (ADR-029): lê qualquer texto para a palete, depois
        para os 2 cestos (não há matrículas reais fixas nenhures, o
        gate só regista o que for lido).
      - Depois da montagem, 4 tarefas de picking, cada uma com o EAN
        real da linha para testar o scan a sério — uma delas
        (560673995077) tem stock em 2 alvéolos, para testar o ecrã de
        escolha (ADR-022).
*/

SET NOCOUNT ON;
GO

-------------------------------------------------------------------------
-- Zona + Alvéolos de teste
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM dbo.zonas WHERE Id = N'zona-teste-a')
    INSERT INTO dbo.zonas (Id, Codigo, Nome) VALUES (N'zona-teste-a', N'ZT-A', N'Zona de Teste A');
GO

IF NOT EXISTS (SELECT 1 FROM dbo.alv WHERE Id = N'alv-teste-01')
    INSERT INTO dbo.alv (Id, Codigo, ZonaId, Tipo, Corredor, Coluna, Nivel)
    VALUES (N'alv-teste-01', N'ZT-A-01-01', N'zona-teste-a', N'Picking', N'A', 1, 1);
IF NOT EXISTS (SELECT 1 FROM dbo.alv WHERE Id = N'alv-teste-02')
    INSERT INTO dbo.alv (Id, Codigo, ZonaId, Tipo, Corredor, Coluna, Nivel)
    VALUES (N'alv-teste-02', N'ZT-A-01-02', N'zona-teste-a', N'Picking', N'A', 1, 2);
IF NOT EXISTS (SELECT 1 FROM dbo.alv WHERE Id = N'alv-teste-03')
    INSERT INTO dbo.alv (Id, Codigo, ZonaId, Tipo, Corredor, Coluna, Nivel)
    VALUES (N'alv-teste-03', N'ZT-A-02-01', N'zona-teste-a', N'Picking', N'A', 2, 1);
IF NOT EXISTS (SELECT 1 FROM dbo.alv WHERE Id = N'alv-teste-04')
    INSERT INTO dbo.alv (Id, Codigo, ZonaId, Tipo, Corredor, Coluna, Nivel)
    VALUES (N'alv-teste-04', N'ZT-A-02-02', N'zona-teste-a', N'Picking', N'A', 2, 2);
GO

-------------------------------------------------------------------------
-- Artigos de teste -- Sku/Ean são o código de barras REAL de cada linha
-- (pedido 21628); descrição/dimensões/peso unitário são estimados a
-- partir do vol_pick/peso_linha/qtd reais de cada linha (o PHC só deu
-- o total já calculado, não a ficha do artigo) -- aproximados, não
-- reverse-engineered com precisão.
-------------------------------------------------------------------------

MERGE dbo.artigos AS alvo
USING (VALUES
    (N'TST-560673995077', N'560673995077', N'[TESTE] Copo Água Costa Nova 300ml - Turquesa',        6, 25.0, 20.0, 7.0,  0.110, N'Leve',   NULL),
    (N'TST-560673995485', N'560673995485', N'[TESTE] Prato Sobremesa Costa Nova 21cm - Turquesa',    6, 30.0, 20.0, 9.0,  0.200, N'Leve',   NULL),
    (N'TST-560673996105', N'560673996105', N'[TESTE] Prato Raso Costa Nova 27cm - Turquesa',         6, 30.0, 25.0, 14.0, 0.330, N'Pesado', NULL),
    (N'TST-560673996107', N'560673996107', N'[TESTE] Prato Fundo Costa Nova 24cm - Turquesa',        6, 30.0, 25.0, 14.0, 0.330, N'Pesado', NULL)
) AS novo (Sku, Ean, Descricao, UnidadesPorCaixa, ComprimentoCaixaCm, LarguraCaixaCm, AlturaCaixaCm, PesoUnitarioKg, ClasseEmpilhamento, CaixasPorPaleteCompleta)
ON alvo.Sku = novo.Sku
WHEN MATCHED THEN
    UPDATE SET Ean = novo.Ean, Descricao = novo.Descricao, UnidadesPorCaixa = novo.UnidadesPorCaixa,
        ComprimentoCaixaCm = novo.ComprimentoCaixaCm, LarguraCaixaCm = novo.LarguraCaixaCm, AlturaCaixaCm = novo.AlturaCaixaCm,
        PesoUnitarioKg = novo.PesoUnitarioKg, ClasseEmpilhamento = novo.ClasseEmpilhamento
WHEN NOT MATCHED THEN
    INSERT (Sku, Ean, Descricao, UnidadesPorCaixa, ComprimentoCaixaCm, LarguraCaixaCm, AlturaCaixaCm, PesoUnitarioKg, ClasseEmpilhamento, CaixasPorPaleteCompleta)
    VALUES (novo.Sku, novo.Ean, novo.Descricao, novo.UnidadesPorCaixa, novo.ComprimentoCaixaCm, novo.LarguraCaixaCm, novo.AlturaCaixaCm, novo.PesoUnitarioKg, novo.ClasseEmpilhamento, novo.CaixasPorPaleteCompleta);
GO

-------------------------------------------------------------------------
-- Stock por alvéolo (SA) -- 560673995077 de propósito em 2 alvéolos,
-- para testar o ecrã de escolha (ADR-022). Quantidades sempre acima do
-- qtd real da linha (ver secção seguinte), com alguma folga.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM dbo.sa WHERE Sku = N'TST-560673995077' AND AlveoloId = N'alv-teste-01')
    INSERT INTO dbo.sa (Sku, AlveoloId, Quantidade) VALUES (N'TST-560673995077', N'alv-teste-01', 10);
IF NOT EXISTS (SELECT 1 FROM dbo.sa WHERE Sku = N'TST-560673995077' AND AlveoloId = N'alv-teste-02')
    INSERT INTO dbo.sa (Sku, AlveoloId, Quantidade) VALUES (N'TST-560673995077', N'alv-teste-02', 10);
IF NOT EXISTS (SELECT 1 FROM dbo.sa WHERE Sku = N'TST-560673995485' AND AlveoloId = N'alv-teste-02')
    INSERT INTO dbo.sa (Sku, AlveoloId, Quantidade) VALUES (N'TST-560673995485', N'alv-teste-02', 50);
IF NOT EXISTS (SELECT 1 FROM dbo.sa WHERE Sku = N'TST-560673996105' AND AlveoloId = N'alv-teste-03')
    INSERT INTO dbo.sa (Sku, AlveoloId, Quantidade) VALUES (N'TST-560673996105', N'alv-teste-03', 50);
IF NOT EXISTS (SELECT 1 FROM dbo.sa WHERE Sku = N'TST-560673996107' AND AlveoloId = N'alv-teste-04')
    INSERT INTO dbo.sa (Sku, AlveoloId, Quantidade) VALUES (N'TST-560673996107', N'alv-teste-04', 50);
GO

-------------------------------------------------------------------------
-- Ordem de Preparação de teste -- REAL (ordem 1113/pedido 21628/numpf
-- 96123, Glas In Loodbedrijf Van Dommelen BV, P2, 1 plataforma, ADR-032),
-- já tipificada e despachada.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM dbo.ordenspreparacao WHERE Id = N'op-teste-01')
BEGIN
    INSERT INTO dbo.ordenspreparacao
        (Id, Cliente, DataEntrega, MoradaEntrega, Estado, AlturaPaleteCm,
         ReferenciaExterna, NumeroOrdem, NumeroPedido, NumeroProforma,
         TipoPlataformaCodigo, NPlataformas, NumRefs, TotalCaixas,
         VolumeTotalCm3, PesoTotalKg, RefsSemFicha, Observacoes)
    VALUES
        -- ReferenciaExterna: bostamp real vem truncado na amostra
        -- partilhada (5C53A611-2DC6-4F31-A726-...) -- sem os últimos
        -- carateres não dá para usar tal como está, por isso este é um
        -- GUID de teste à parte, não o bostamp verdadeiro.
        (N'op-teste-01', N'Glas In Loodbedrijf Van Dommelen BV', NULL, NULL, N'Despachada', 140,
         N'a1b2c3d4-e5f6-47a8-9b1c-000000000001', 1113, 21628, 96123,
         N'P2', 1, 4, 18,
         140280.000, 27.78, 0, N'26/08 - encomenda única - Etiqueta EU');
END
GO

IF NOT EXISTS (SELECT 1 FROM dbo.ordensseparacao WHERE Id = N'ps-teste-01')
BEGIN
    INSERT INTO dbo.ordensseparacao (Id, OrdemPreparacaoId, NumeroDocumento, Origem, Canal)
    VALUES (N'ps-teste-01', N'op-teste-01', N'21628', N'PHC', NULL);
END
GO

IF NOT EXISTS (SELECT 1 FROM dbo.plataformas WHERE Id = N'plat-teste-01')
BEGIN
    INSERT INTO dbo.plataformas (Id, Codigo, OrdemPreparacaoId, TipoPlataformaCodigo, IndiceCamada, ClasseCamada, Estado)
    VALUES (N'plat-teste-01', N'PLT-TESTE-01', N'op-teste-01', N'P2', NULL, NULL, N'EmPicking');
END
GO

-- Linhas reais do pedido 21628: artigo (EAN), qtd.
MERGE dbo.ordensseparacaolinhas AS alvo
USING (VALUES
    (N'ps-linha-teste-1', N'ps-teste-01', N'TST-560673995077', 18, N'alv-teste-01', N'plat-teste-01'),
    (N'ps-linha-teste-2', N'ps-teste-01', N'TST-560673995485', 30, N'alv-teste-02', N'plat-teste-01'),
    (N'ps-linha-teste-3', N'ps-teste-01', N'TST-560673996105', 30, N'alv-teste-03', N'plat-teste-01'),
    (N'ps-linha-teste-4', N'ps-teste-01', N'TST-560673996107', 30, N'alv-teste-04', N'plat-teste-01')
) AS novo (Id, OrdemSeparacaoId, Sku, Quantidade, AlveoloId, PlataformaId)
ON alvo.Id = novo.Id
WHEN NOT MATCHED THEN
    INSERT (Id, OrdemSeparacaoId, Sku, Quantidade, AlveoloId, PlataformaId)
    VALUES (novo.Id, novo.OrdemSeparacaoId, novo.Sku, novo.Quantidade, novo.AlveoloId, novo.PlataformaId);
GO

-------------------------------------------------------------------------
-- Missão de picking de teste -- Estado "Criada" de propósito: o pda
-- atribui-a sozinho na primeira vez que perguntar por trabalho (ADR-016).
-- PlataformaConfirmada fica no valor por omissão (0/false) -- o gate de
-- montagem (ADR-029) é o primeiro ecrã a aparecer.
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM dbo.missao WHERE Id = N'missao-teste-01')
BEGIN
    INSERT INTO dbo.missao (Id, Codigo, CentroTrabalho, ZonaId, PlataformaId, Estado)
    VALUES (N'missao-teste-01', N'M-TESTE-01', N'Picking', N'zona-teste-a', N'plat-teste-01', N'Criada');
END
GO

MERGE dbo.missaolinhas AS alvo
USING (VALUES
    (N'missaolinha-teste-1', N'missao-teste-01', N'TST-560673995077', N'[TESTE] Copo Água Costa Nova 300ml - Turquesa',     N'560673995077', N'alv-teste-01', N'PLT-TESTE-01', N'P2', 18),
    (N'missaolinha-teste-2', N'missao-teste-01', N'TST-560673995485', N'[TESTE] Prato Sobremesa Costa Nova 21cm - Turquesa', N'560673995485', N'alv-teste-02', N'PLT-TESTE-01', N'P2', 30),
    (N'missaolinha-teste-3', N'missao-teste-01', N'TST-560673996105', N'[TESTE] Prato Raso Costa Nova 27cm - Turquesa',      N'560673996105', N'alv-teste-03', N'PLT-TESTE-01', N'P2', 30),
    (N'missaolinha-teste-4', N'missao-teste-01', N'TST-560673996107', N'[TESTE] Prato Fundo Costa Nova 24cm - Turquesa',     N'560673996107', N'alv-teste-04', N'PLT-TESTE-01', N'P2', 30)
) AS novo (Id, MissaoId, Sku, Descricao, CodigoBarras, AlveoloId, Plataforma, TipoPlataformaCodigo, QuantidadeAlvo)
ON alvo.Id = novo.Id
WHEN MATCHED THEN
    UPDATE SET Descricao = novo.Descricao, CodigoBarras = novo.CodigoBarras
WHEN NOT MATCHED THEN
    INSERT (Id, MissaoId, Sku, Descricao, CodigoBarras, AlveoloId, Plataforma, TipoPlataformaCodigo, QuantidadeAlvo)
    VALUES (novo.Id, novo.MissaoId, novo.Sku, novo.Descricao, novo.CodigoBarras, novo.AlveoloId, novo.Plataforma, novo.TipoPlataformaCodigo, novo.QuantidadeAlvo);
GO

PRINT 'Dados de teste prontos -- 1 missão de picking (M-TESTE-01, Zona de Teste A, plataforma P2 por montar).';
GO

/*
    Para apagar só os dados de teste mais tarde (sem afetar dados
    reais entretanto recebidos), por esta ordem:

      DELETE FROM dbo.operacoesprocessadas WHERE MissaoLinhaId LIKE N'missaolinha-teste-%';
      DELETE FROM dbo.missaolinhas WHERE Id LIKE N'missaolinha-teste-%';
      DELETE FROM dbo.missao WHERE Id = N'missao-teste-01';
      DELETE FROM dbo.ordensseparacaolinhas WHERE Id LIKE N'ps-linha-teste-%';
      DELETE FROM dbo.ordensseparacao WHERE Id = N'ps-teste-01';
      DELETE FROM dbo.plataformas WHERE Id = N'plat-teste-01';
      DELETE FROM dbo.ordenspreparacao WHERE Id = N'op-teste-01';
      DELETE FROM dbo.sa WHERE AlveoloId LIKE N'alv-teste-%';
      DELETE FROM dbo.artigos WHERE Sku LIKE N'TST-%';
      DELETE FROM dbo.alv WHERE Id LIKE N'alv-teste-%';
      DELETE FROM dbo.zonas WHERE Id = N'zona-teste-a';
*/
