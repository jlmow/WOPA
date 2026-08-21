/*
    WOPA — dados de teste para testar num terminal Android (leitura de
    código de barras)
    =====================================================================

    5 Ordens de Preparação, todas com cabeçalho + linhas REAIS —
    amostra do PHC que o cliente partilhou. Cada uma foi conferida à
    mão: soma de caixas_nec/vol_pick/peso_linha das linhas bate certo
    com total_caixas/vol_total_cm3/peso_total_kg do cabeçalho.

      A) Ordem 1113 / pedido 21628 / numpf 96123 -- Glas In Loodbedrijf
         Van Dommelen BV -- P2 (2 cestos), 1 plataforma, 4 refs.
      B) Ordem 1132 / pedido 21720 / numpf 96185 -- Maison Truffe AG --
         P4 (4 cestos), 1 plataforma, 2 refs.
      C) Ordem 1127 / pedido 21230 / numpf 95894 -- Ego Dekor s.r.o. --
         P4 (4 cestos), 1 plataforma, 5 refs.
      D) Ordem 1116 / pedido 21139 / numpf 95307 -- José Maria Araújo
         Lda -- P1 (1 cesto), 1 plataforma, 7 refs.
      E) Ordem 1105 / pedido 21579 / numpf 96118 -- Sligro Food Group
         Nederland B.V. -- P1(4): 4 plataformas P1, 6 refs distribuídos
         por elas em round-robin (mesma lógica do POST /tipificar) --
         4 missões separadas, uma por plataforma, tal como o despacho
         real faz (cada Plataforma tem a sua própria Missão).

    Só o que o cliente ainda não enviou foi inventado: descrição de
    artigo, dimensões de caixa/peso unitário (o PHC só deu o total já
    calculado por linha, não a ficha do artigo -- dimensões
    aproximadas a partir de vol_pick/caixas_nec, não exatas), zona/
    alvéolos, paletes/cestos e o stock. Isto não bloqueia nenhum teste
    -- a tipificação já vem decidida (ADR-032), a cubicagem do WOPA nem
    entra em jogo para nenhuma destas Ordens.

    Todos os IDs de zona/alvéolo/plataforma/missão/palete/cesto têm
    prefixo "teste"/"TST-" de propósito -- fácil de identificar e de
    apagar mais tarde (ver fundo do ficheiro).

    ADR-035 -- Paletes de origem (stock) e Paletes de missão (montagem)
    são a MESMA tabela (equipamento reaproveitado, ver ARCHITECTURE.md):
      - Paletes de ORIGEM: já têm stock (SA), por isso já vêm com
        LocalizacaoAtualId = o alvéolo onde estão paradas. O pda recusa
        um pick sem o operador ler a matrícula certa -- por isso
        alv-teste-02 fica com 2 paletes (SKUs diferentes na mesma) e
        alv-teste-03 fica com 2 paletes do MESMO SKU (quantidade
        dividida) -- os dois casos que a validação tem de aguentar.
      - Paletes de MISSÃO: vêm do depósito de paletes vazias (Ativa=1,
        sem LocalizacaoAtualId -- "em circulação"), uma por Plataforma,
        para o operador ler no gate de montagem (ADR-029). O pda
        também recusa uma matrícula de montagem desconhecida.
      - Cestos: mesma lógica -- pré-carregados aqui, um conjunto por
        Plataforma conforme o tipo (P1=1, P2=2, P4=4 cestos).

    Como correr (depois de reset-database.sql + schema.sql):
      sqlcmd -S <servidor> -d WOPA -E -f 65001 -i dados-teste.sql

    "Uma missão de cada vez" (ADR-008): o pda só mostra a mais antiga
    ainda não concluída -- as 8 missões (A, B, C, D, E1-E4) ficam numa
    fila, pela ordem em que este script as insere. Cada uma pede
    montagem própria (P1/P2/P4 conforme o caso) antes de picar artigos.
*/

SET NOCOUNT ON;
GO

-------------------------------------------------------------------------
-- Zona de teste (partilhada por todas as Ordens) + Alvéolos
-------------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM dbo.zonas WHERE Id = N'zona-teste-a')
    INSERT INTO dbo.zonas (Id, Codigo, Nome) VALUES (N'zona-teste-a', N'ZT-A', N'Zona de Teste A');
GO

MERGE dbo.alv AS alvo
USING (VALUES
    -- Ordem A (Glas, pedido 21628)
    (N'alv-teste-01', N'ZT-A-01-01', N'zona-teste-a', N'Picking', N'A', 1, 1),
    (N'alv-teste-02', N'ZT-A-01-02', N'zona-teste-a', N'Picking', N'A', 1, 2),
    (N'alv-teste-03', N'ZT-A-02-01', N'zona-teste-a', N'Picking', N'A', 2, 1),
    (N'alv-teste-04', N'ZT-A-02-02', N'zona-teste-a', N'Picking', N'A', 2, 2),
    -- Ordem B (Maison Truffe, pedido 21720)
    (N'alv-teste-05', N'ZT-B-01-01', N'zona-teste-a', N'Picking', N'B', 1, 1),
    (N'alv-teste-06', N'ZT-B-01-02', N'zona-teste-a', N'Picking', N'B', 1, 2),
    -- Ordem C (Ego Dekor, pedido 21230)
    (N'alv-teste-07', N'ZT-C-01-01', N'zona-teste-a', N'Picking', N'C', 1, 1),
    (N'alv-teste-08', N'ZT-C-01-02', N'zona-teste-a', N'Picking', N'C', 1, 2),
    (N'alv-teste-09', N'ZT-C-02-01', N'zona-teste-a', N'Picking', N'C', 2, 1),
    (N'alv-teste-10', N'ZT-C-02-02', N'zona-teste-a', N'Picking', N'C', 2, 2),
    (N'alv-teste-11', N'ZT-C-02-03', N'zona-teste-a', N'Picking', N'C', 2, 3),
    -- Ordem D (José Maria Araújo, pedido 21139)
    (N'alv-teste-12', N'ZT-D-01-01', N'zona-teste-a', N'Picking', N'D', 1, 1),
    (N'alv-teste-13', N'ZT-D-01-02', N'zona-teste-a', N'Picking', N'D', 1, 2),
    (N'alv-teste-14', N'ZT-D-01-03', N'zona-teste-a', N'Picking', N'D', 1, 3),
    (N'alv-teste-15', N'ZT-D-02-01', N'zona-teste-a', N'Picking', N'D', 2, 1),
    (N'alv-teste-16', N'ZT-D-02-02', N'zona-teste-a', N'Picking', N'D', 2, 2),
    (N'alv-teste-17', N'ZT-D-02-03', N'zona-teste-a', N'Picking', N'D', 2, 3),
    (N'alv-teste-18', N'ZT-D-02-04', N'zona-teste-a', N'Picking', N'D', 2, 4),
    -- Ordem E (Sligro, pedido 21579, 4 plataformas)
    (N'alv-teste-19', N'ZT-E-01-01', N'zona-teste-a', N'Picking', N'E', 1, 1),
    (N'alv-teste-20', N'ZT-E-01-02', N'zona-teste-a', N'Picking', N'E', 1, 2),
    (N'alv-teste-21', N'ZT-E-01-03', N'zona-teste-a', N'Picking', N'E', 1, 3),
    (N'alv-teste-22', N'ZT-E-02-01', N'zona-teste-a', N'Picking', N'E', 2, 1),
    (N'alv-teste-23', N'ZT-E-02-02', N'zona-teste-a', N'Picking', N'E', 2, 2),
    (N'alv-teste-24', N'ZT-E-02-03', N'zona-teste-a', N'Picking', N'E', 2, 3)
) AS novo (Id, Codigo, ZonaId, Tipo, Corredor, Coluna, Nivel)
ON alvo.Id = novo.Id
WHEN NOT MATCHED THEN
    INSERT (Id, Codigo, ZonaId, Tipo, Corredor, Coluna, Nivel)
    VALUES (novo.Id, novo.Codigo, novo.ZonaId, novo.Tipo, novo.Corredor, novo.Coluna, novo.Nivel);
GO

-------------------------------------------------------------------------
-- Paletes de teste (ADR-035) -- equipamento pré-carregado, tal como o
-- ecrã "Equipamento" do controller faria. Duas famílias:
--   - Origem: já paradas num alvéolo, com stock (SA mais abaixo).
--   - Missão: no depósito, sem localização -- para o gate de montagem.
-------------------------------------------------------------------------

MERGE dbo.paletes AS alvo
USING (VALUES
    -- Origem -- Ordem A (alv-teste-02 com 2 paletes de SKUs diferentes;
    -- alv-teste-03 com 2 paletes do MESMO SKU, quantidade dividida)
    (N'palete-teste-a01',  N'TST-PAL-A01',  N'alv-teste-01'),
    (N'palete-teste-a02',  N'TST-PAL-A02',  N'alv-teste-02'),
    (N'palete-teste-a03a', N'TST-PAL-A03A', N'alv-teste-03'),
    (N'palete-teste-a03b', N'TST-PAL-A03B', N'alv-teste-03'),
    (N'palete-teste-a04',  N'TST-PAL-A04',  N'alv-teste-04'),
    -- Origem -- Ordem B
    (N'palete-teste-b05',  N'TST-PAL-B05',  N'alv-teste-05'),
    (N'palete-teste-b06',  N'TST-PAL-B06',  N'alv-teste-06'),
    -- Origem -- Ordem C
    (N'palete-teste-c07',  N'TST-PAL-C07',  N'alv-teste-07'),
    (N'palete-teste-c08',  N'TST-PAL-C08',  N'alv-teste-08'),
    (N'palete-teste-c09',  N'TST-PAL-C09',  N'alv-teste-09'),
    (N'palete-teste-c10',  N'TST-PAL-C10',  N'alv-teste-10'),
    (N'palete-teste-c11',  N'TST-PAL-C11',  N'alv-teste-11'),
    -- Origem -- Ordem D
    (N'palete-teste-d12',  N'TST-PAL-D12',  N'alv-teste-12'),
    (N'palete-teste-d13',  N'TST-PAL-D13',  N'alv-teste-13'),
    (N'palete-teste-d14',  N'TST-PAL-D14',  N'alv-teste-14'),
    (N'palete-teste-d15',  N'TST-PAL-D15',  N'alv-teste-15'),
    (N'palete-teste-d16',  N'TST-PAL-D16',  N'alv-teste-16'),
    (N'palete-teste-d17',  N'TST-PAL-D17',  N'alv-teste-17'),
    (N'palete-teste-d18',  N'TST-PAL-D18',  N'alv-teste-18'),
    -- Origem -- Ordem E
    (N'palete-teste-e19',  N'TST-PAL-E19',  N'alv-teste-19'),
    (N'palete-teste-e20',  N'TST-PAL-E20',  N'alv-teste-20'),
    (N'palete-teste-e21',  N'TST-PAL-E21',  N'alv-teste-21'),
    (N'palete-teste-e22',  N'TST-PAL-E22',  N'alv-teste-22'),
    (N'palete-teste-e23',  N'TST-PAL-E23',  N'alv-teste-23'),
    (N'palete-teste-e24',  N'TST-PAL-E24',  N'alv-teste-24'),
    -- Missão -- uma palete de depósito por Plataforma, para montar
    (N'palete-teste-mont-a',  N'TST-PAL-MONT-A',  NULL),
    (N'palete-teste-mont-b',  N'TST-PAL-MONT-B',  NULL),
    (N'palete-teste-mont-c',  N'TST-PAL-MONT-C',  NULL),
    (N'palete-teste-mont-d',  N'TST-PAL-MONT-D',  NULL),
    (N'palete-teste-mont-e1', N'TST-PAL-MONT-E1', NULL),
    (N'palete-teste-mont-e2', N'TST-PAL-MONT-E2', NULL),
    (N'palete-teste-mont-e3', N'TST-PAL-MONT-E3', NULL),
    (N'palete-teste-mont-e4', N'TST-PAL-MONT-E4', NULL)
) AS novo (Id, Matricula, LocalizacaoAtualId)
ON alvo.Id = novo.Id
WHEN NOT MATCHED THEN
    INSERT (Id, Matricula, LocalizacaoAtualId)
    VALUES (novo.Id, novo.Matricula, novo.LocalizacaoAtualId);
GO

-------------------------------------------------------------------------
-- Cestos de teste (ADR-030/035) -- um conjunto por Plataforma, conforme
-- o tipo (P1=1, P2=2, P4=4), todos do único tipo de cesto seedado
-- ("cesto-standard").
-------------------------------------------------------------------------

MERGE dbo.cestoinstancias AS alvo
USING (VALUES
    (N'cesto-teste-a1', N'TST-CESTO-A1'),
    (N'cesto-teste-a2', N'TST-CESTO-A2'),
    (N'cesto-teste-b1', N'TST-CESTO-B1'),
    (N'cesto-teste-b2', N'TST-CESTO-B2'),
    (N'cesto-teste-b3', N'TST-CESTO-B3'),
    (N'cesto-teste-b4', N'TST-CESTO-B4'),
    (N'cesto-teste-c1', N'TST-CESTO-C1'),
    (N'cesto-teste-c2', N'TST-CESTO-C2'),
    (N'cesto-teste-c3', N'TST-CESTO-C3'),
    (N'cesto-teste-c4', N'TST-CESTO-C4'),
    (N'cesto-teste-d1', N'TST-CESTO-D1'),
    (N'cesto-teste-e1', N'TST-CESTO-E1'),
    (N'cesto-teste-e2', N'TST-CESTO-E2'),
    (N'cesto-teste-e3', N'TST-CESTO-E3'),
    (N'cesto-teste-e4', N'TST-CESTO-E4')
) AS novo (Id, Matricula)
ON alvo.Id = novo.Id
WHEN NOT MATCHED THEN
    INSERT (Id, Matricula, TipoCestoId)
    VALUES (novo.Id, novo.Matricula, N'cesto-standard');
GO

-------------------------------------------------------------------------
-- Artigos de teste -- Sku/Ean são o código de barras REAL de cada
-- linha; descrição/dimensões/peso unitário estimados a partir de
-- vol_pick/peso_linha/qtd/caixas_nec reais (o PHC só deu o total já
-- calculado, não a ficha do artigo) -- aproximados, não
-- reverse-engineered com precisão.
-------------------------------------------------------------------------

MERGE dbo.artigos AS alvo
USING (VALUES
    -- Ordem A (Glas, Turquesa)
    (N'TST-560673995077', N'560673995077', N'[TESTE] Copo Água Costa Nova 300ml - Turquesa',        6, 25.0, 20.0, 7.0,  0.110, N'Leve',   NULL),
    (N'TST-560673995485', N'560673995485', N'[TESTE] Prato Sobremesa Costa Nova 21cm - Turquesa',    6, 30.0, 20.0, 9.0,  0.200, N'Leve',   NULL),
    (N'TST-560673996105', N'560673996105', N'[TESTE] Prato Raso Costa Nova 27cm - Turquesa',         6, 30.0, 25.0, 14.0, 0.330, N'Pesado', NULL),
    (N'TST-560673996107', N'560673996107', N'[TESTE] Prato Fundo Costa Nova 24cm - Turquesa',        6, 30.0, 25.0, 14.0, 0.330, N'Pesado', NULL),
    -- Ordem B (Maison Truffe, Basalto)
    (N'TST-560673993773', N'560673993773', N'[TESTE] Chávena Costa Nova 200ml - Basalto',           12, 11.0, 10.0, 5.0,  0.038, N'Leve',   NULL),
    (N'TST-560673993777', N'560673993777', N'[TESTE] Pires Costa Nova 15cm - Basalto',               12, 10.0, 8.0,  5.0,  0.022, N'Leve',   NULL),
    -- Ordem C (Ego Dekor, Areia)
    (N'TST-560673998092', N'560673998092', N'[TESTE] Taça Molho Costa Nova 8cm - Areia',              6, 13.0, 13.0, 13.0, 0.155, N'Leve',   NULL),
    (N'TST-560673998328', N'560673998328', N'[TESTE] Terrina Costa Nova 25cm - Areia',                6, 26.0, 24.0, 18.0, 0.432, N'Pesado', NULL),
    (N'TST-560673998403', N'560673998403', N'[TESTE] Terrina Grande Costa Nova 30cm - Areia',         1, 22.0, 20.0, 10.0, 1.600, N'Pesado', NULL),
    (N'TST-560673998404', N'560673998404', N'[TESTE] Travessa Oval Costa Nova 40cm - Areia',          1, 22.0, 20.0, 10.0, 1.600, N'Pesado', NULL),
    (N'TST-560673998406', N'560673998406', N'[TESTE] Saladeira Costa Nova 28cm - Areia',              1, 22.0, 20.0, 10.0, 1.600, N'Pesado', NULL),
    -- Ordem D (José Maria Araújo, Ocre)
    (N'TST-560673991108', N'560673991108', N'[TESTE] Jarra Costa Nova 30cm - Ocre',                   1, 34.0, 31.0, 30.0, 1.830, N'Pesado', NULL),
    (N'TST-560673993425', N'560673993425', N'[TESTE] Vaso Costa Nova 35cm - Ocre',                    1, 36.0, 33.0, 32.0, 1.485, N'Pesado', NULL),
    (N'TST-560673995223', N'560673995223', N'[TESTE] Fruteira Costa Nova 32cm - Ocre',                1, 28.0, 24.0, 28.0, 2.518, N'Pesado', NULL),
    (N'TST-560673997187', N'560673997187', N'[TESTE] Marcador de Lugar Costa Nova - Ocre',            6, 18.0, 15.0, 18.0, 0.180, N'Leve',   NULL),
    (N'TST-560673997196', N'560673997196', N'[TESTE] Conjunto Sal e Pimenta Costa Nova - Ocre',       2, 23.0, 20.0, 17.0, 1.170, N'Leve',   NULL),
    (N'TST-560673998105', N'560673998105', N'[TESTE] Centro de Mesa Costa Nova 40cm - Ocre',          1, 25.0, 21.0, 21.0, 2.000, N'Pesado', NULL),
    (N'TST-560673998341', N'560673998341', N'[TESTE] Bowl Decorativo Costa Nova 45cm - Ocre',         1, 32.0, 32.0, 16.0, 1.606, N'Pesado', NULL),
    -- Ordem E (Sligro, Branco, catering)
    (N'TST-560673995388', N'560673995388', N'[TESTE] Travessa Buffet Costa Nova 45cm - Branco',       6, 34.0, 26.0, 20.0, 0.745, N'Pesado', NULL),
    (N'TST-560673995382', N'560673995382', N'[TESTE] Prato Sobremesa Costa Nova 19cm - Branco',       6, 28.0, 20.0, 10.0, 0.250, N'Leve',   NULL),
    (N'TST-560673995392', N'560673995392', N'[TESTE] Prato Raso Costa Nova 26cm - Branco',            6, 33.0, 21.0, 10.0, 0.488, N'Pesado', NULL),
    (N'TST-560673995480', N'560673995480', N'[TESTE] Taça Costa Nova 16cm - Branco',                  6, 26.0, 21.0, 10.0, 0.200, N'Leve',   NULL),
    (N'TST-560673995483', N'560673995483', N'[TESTE] Pires Costa Nova 17cm - Branco',                 6, 26.0, 21.0, 10.0, 0.200, N'Leve',   NULL),
    (N'TST-560673995486', N'560673995486', N'[TESTE] Chávena Costa Nova 220ml - Branco',              6, 26.0, 21.0, 10.0, 0.200, N'Leve',   NULL)
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
-- Stock por alvéolo+palete (SA, ADR-035 -- chave composta Sku+AlveoloId+
-- PaleteId) -- sempre acima do qtd real da linha, com alguma folga.
-- 560673995077 (Ordem A) de propósito em 2 alvéolos (ecrã de escolha de
-- alvéolo, ADR-022); 560673996105 (Ordem A) de propósito em 2 paletes no
-- MESMO alvéolo (o operador tem de ler a palete certa antes de picar,
-- ADR-035) -- a soma por alvéolo continua a bater com o total original.
-------------------------------------------------------------------------

MERGE dbo.sa AS alvo
USING (VALUES
    -- Ordem A
    (N'TST-560673995077', N'alv-teste-01', N'palete-teste-a01',  10),
    (N'TST-560673995077', N'alv-teste-02', N'palete-teste-a02',  10),
    (N'TST-560673995485', N'alv-teste-02', N'palete-teste-a02',  50),
    (N'TST-560673996105', N'alv-teste-03', N'palete-teste-a03a', 30),
    (N'TST-560673996105', N'alv-teste-03', N'palete-teste-a03b', 20),
    (N'TST-560673996107', N'alv-teste-04', N'palete-teste-a04',  50),
    -- Ordem B
    (N'TST-560673993773', N'alv-teste-05', N'palete-teste-b05', 30),
    (N'TST-560673993777', N'alv-teste-06', N'palete-teste-b06', 30),
    -- Ordem C
    (N'TST-560673998092', N'alv-teste-07', N'palete-teste-c07', 20),
    (N'TST-560673998328', N'alv-teste-08', N'palete-teste-c08', 30),
    (N'TST-560673998403', N'alv-teste-09', N'palete-teste-c09', 10),
    (N'TST-560673998404', N'alv-teste-10', N'palete-teste-c10', 10),
    (N'TST-560673998406', N'alv-teste-11', N'palete-teste-c11', 10),
    -- Ordem D
    (N'TST-560673991108', N'alv-teste-12', N'palete-teste-d12', 10),
    (N'TST-560673993425', N'alv-teste-13', N'palete-teste-d13', 10),
    (N'TST-560673995223', N'alv-teste-14', N'palete-teste-d14', 10),
    (N'TST-560673997187', N'alv-teste-15', N'palete-teste-d15', 20),
    (N'TST-560673997196', N'alv-teste-16', N'palete-teste-d16', 20),
    (N'TST-560673998105', N'alv-teste-17', N'palete-teste-d17', 10),
    (N'TST-560673998341', N'alv-teste-18', N'palete-teste-d18', 10),
    -- Ordem E
    (N'TST-560673995388', N'alv-teste-19', N'palete-teste-e19', 150),
    (N'TST-560673995382', N'alv-teste-20', N'palete-teste-e20', 200),
    (N'TST-560673995392', N'alv-teste-21', N'palete-teste-e21', 200),
    (N'TST-560673995480', N'alv-teste-22', N'palete-teste-e22', 220),
    (N'TST-560673995483', N'alv-teste-23', N'palete-teste-e23', 200),
    (N'TST-560673995486', N'alv-teste-24', N'palete-teste-e24', 220)
) AS novo (Sku, AlveoloId, PaleteId, Quantidade)
ON alvo.Sku = novo.Sku AND alvo.AlveoloId = novo.AlveoloId AND alvo.PaleteId = novo.PaleteId
WHEN NOT MATCHED THEN
    INSERT (Sku, AlveoloId, PaleteId, Quantidade) VALUES (novo.Sku, novo.AlveoloId, novo.PaleteId, novo.Quantidade);
GO

-------------------------------------------------------------------------
-- Ordens de Preparação -- cabeçalhos REAIS (ADR-032), já tipificadas e
-- despachadas.
-------------------------------------------------------------------------

MERGE dbo.ordenspreparacao AS alvo
USING (VALUES
    -- Id, Cliente, Estado, AlturaPaleteCm, ReferenciaExterna, NumeroOrdem, NumeroPedido, NumeroProforma, TipoPlataformaCodigo, NPlataformas, NumRefs, TotalCaixas, VolumeTotalCm3, PesoTotalKg, RefsSemFicha, Observacoes
    (N'op-teste-a', N'Glas In Loodbedrijf Van Dommelen BV',    N'Despachada', 140, N'a1b2c3d4-e5f6-47a8-9b1c-00000000000a', 1113, 21628, 96123, N'P2', 1, 4, 18,  140280.000,  27.78,  0, N'26/08 - encomenda única - Etiqueta EU'),
    (N'op-teste-b', N'Maison Truffe AG',                       N'Despachada', 140, N'a1b2c3d4-e5f6-47a8-9b1c-00000000000b', 1132, 21720, 96185, N'P4', 1, 2, 2,   950.000,     0.72,   0, N'28/08 - segue junto - EX-OUT - F.D.'),
    (N'op-teste-c', N'Ego Dekor s.r.o.',                       N'Despachada', 140, N'a1b2c3d4-e5f6-47a8-9b1c-00000000000c', 1127, 21230, 95894, N'P4', 1, 5, 9,   51628.168,   15.71,  0, N'28/08 - segue junto - Etiqueta EU - F.D.'),
    (N'op-teste-d', N'José Maria Araújo Lda',                  N'Despachada', 140, N'a1b2c3d4-e5f6-47a8-9b1c-00000000000d', 1116, 21139, 95307, N'P1', 1, 7, 18,  223657.135,  33.51,  0, N'28/08 - segue junto PT'),
    (N'op-teste-e', N'Sligro Food Group Nederland B.V.',       N'Despachada', 140, N'a1b2c3d4-e5f6-47a8-9b1c-00000000000e', 1105, 21579, 96118, N'P1', 4, 6, 177, 1260673.000, 336.91, 0, N'26/08 - segue junto - Etq. caixa - Não mix PI + Ref.')
) AS novo (Id, Cliente, Estado, AlturaPaleteCm, ReferenciaExterna, NumeroOrdem, NumeroPedido, NumeroProforma, TipoPlataformaCodigo, NPlataformas, NumRefs, TotalCaixas, VolumeTotalCm3, PesoTotalKg, RefsSemFicha, Observacoes)
ON alvo.Id = novo.Id
WHEN NOT MATCHED THEN
    INSERT (Id, Cliente, Estado, AlturaPaleteCm, ReferenciaExterna, NumeroOrdem, NumeroPedido, NumeroProforma, TipoPlataformaCodigo, NPlataformas, NumRefs, TotalCaixas, VolumeTotalCm3, PesoTotalKg, RefsSemFicha, Observacoes)
    VALUES (novo.Id, novo.Cliente, novo.Estado, novo.AlturaPaleteCm, novo.ReferenciaExterna, novo.NumeroOrdem, novo.NumeroPedido, novo.NumeroProforma, novo.TipoPlataformaCodigo, novo.NPlataformas, novo.NumRefs, novo.TotalCaixas, novo.VolumeTotalCm3, novo.PesoTotalKg, novo.RefsSemFicha, novo.Observacoes);
GO

MERGE dbo.ordensseparacao AS alvo
USING (VALUES
    (N'ps-teste-a', N'op-teste-a', N'21628', N'PHC'),
    (N'ps-teste-b', N'op-teste-b', N'21720', N'PHC'),
    (N'ps-teste-c', N'op-teste-c', N'21230', N'PHC'),
    (N'ps-teste-d', N'op-teste-d', N'21139', N'PHC'),
    (N'ps-teste-e', N'op-teste-e', N'21579', N'PHC')
) AS novo (Id, OrdemPreparacaoId, NumeroDocumento, Origem)
ON alvo.Id = novo.Id
WHEN NOT MATCHED THEN
    INSERT (Id, OrdemPreparacaoId, NumeroDocumento, Origem)
    VALUES (novo.Id, novo.OrdemPreparacaoId, novo.NumeroDocumento, novo.Origem);
GO

-------------------------------------------------------------------------
-- Plataformas -- 1 cada para A/B/C/D; 4 para E (P1(4), IndiceCamada/
-- ClasseCamada calculados como CubicagemService.SequenciaCamadas(4, ...)
-- calcularia: 1 Pesada, 2 Leve, 3 Leve, 4 Pesada). PaleteId fica NULL --
-- só é atribuído quando o operador monta a plataforma no pda (ADR-035).
-------------------------------------------------------------------------

MERGE dbo.plataformas AS alvo
USING (VALUES
    (N'plat-teste-a',  N'PLT-TESTE-A',  N'op-teste-a', N'P2', NULL, NULL),
    (N'plat-teste-b',  N'PLT-TESTE-B',  N'op-teste-b', N'P4', NULL, NULL),
    (N'plat-teste-c',  N'PLT-TESTE-C',  N'op-teste-c', N'P4', NULL, NULL),
    (N'plat-teste-d',  N'PLT-TESTE-D',  N'op-teste-d', N'P1', NULL, NULL),
    (N'plat-teste-e1', N'PLT-TESTE-E1', N'op-teste-e', N'P1', 1, N'Pesada'),
    (N'plat-teste-e2', N'PLT-TESTE-E2', N'op-teste-e', N'P1', 2, N'Leve'),
    (N'plat-teste-e3', N'PLT-TESTE-E3', N'op-teste-e', N'P1', 3, N'Leve'),
    (N'plat-teste-e4', N'PLT-TESTE-E4', N'op-teste-e', N'P1', 4, N'Pesada')
) AS novo (Id, Codigo, OrdemPreparacaoId, TipoPlataformaCodigo, IndiceCamada, ClasseCamada)
ON alvo.Id = novo.Id
WHEN NOT MATCHED THEN
    INSERT (Id, Codigo, OrdemPreparacaoId, TipoPlataformaCodigo, IndiceCamada, ClasseCamada, Estado)
    VALUES (novo.Id, novo.Codigo, novo.OrdemPreparacaoId, novo.TipoPlataformaCodigo, novo.IndiceCamada, novo.ClasseCamada, N'EmPicking');
GO

-------------------------------------------------------------------------
-- Linhas de PS -- reais (código de barras + qtd); PlataformaId já
-- atribuído (round-robin para a Ordem E, tal como o /tipificar faria).
-------------------------------------------------------------------------

MERGE dbo.ordensseparacaolinhas AS alvo
USING (VALUES
    -- Ordem A
    (N'ps-linha-teste-a1', N'ps-teste-a', N'TST-560673995077', 18, N'alv-teste-01', N'plat-teste-a'),
    (N'ps-linha-teste-a2', N'ps-teste-a', N'TST-560673995485', 30, N'alv-teste-02', N'plat-teste-a'),
    (N'ps-linha-teste-a3', N'ps-teste-a', N'TST-560673996105', 30, N'alv-teste-03', N'plat-teste-a'),
    (N'ps-linha-teste-a4', N'ps-teste-a', N'TST-560673996107', 30, N'alv-teste-04', N'plat-teste-a'),
    -- Ordem B
    (N'ps-linha-teste-b1', N'ps-teste-b', N'TST-560673993773', 12, N'alv-teste-05', N'plat-teste-b'),
    (N'ps-linha-teste-b2', N'ps-teste-b', N'TST-560673993777', 12, N'alv-teste-06', N'plat-teste-b'),
    -- Ordem C
    (N'ps-linha-teste-c1', N'ps-teste-c', N'TST-560673998092', 6,  N'alv-teste-07', N'plat-teste-c'),
    (N'ps-linha-teste-c2', N'ps-teste-c', N'TST-560673998328', 12, N'alv-teste-08', N'plat-teste-c'),
    (N'ps-linha-teste-c3', N'ps-teste-c', N'TST-560673998403', 2,  N'alv-teste-09', N'plat-teste-c'),
    (N'ps-linha-teste-c4', N'ps-teste-c', N'TST-560673998404', 2,  N'alv-teste-10', N'plat-teste-c'),
    (N'ps-linha-teste-c5', N'ps-teste-c', N'TST-560673998406', 2,  N'alv-teste-11', N'plat-teste-c'),
    -- Ordem D
    (N'ps-linha-teste-d1', N'ps-teste-d', N'TST-560673991108', 3, N'alv-teste-12', N'plat-teste-d'),
    (N'ps-linha-teste-d2', N'ps-teste-d', N'TST-560673993425', 3, N'alv-teste-13', N'plat-teste-d'),
    (N'ps-linha-teste-d3', N'ps-teste-d', N'TST-560673995223', 2, N'alv-teste-14', N'plat-teste-d'),
    (N'ps-linha-teste-d4', N'ps-teste-d', N'TST-560673997187', 6, N'alv-teste-15', N'plat-teste-d'),
    (N'ps-linha-teste-d5', N'ps-teste-d', N'TST-560673997196', 6, N'alv-teste-16', N'plat-teste-d'),
    (N'ps-linha-teste-d6', N'ps-teste-d', N'TST-560673998105', 2, N'alv-teste-17', N'plat-teste-d'),
    (N'ps-linha-teste-d7', N'ps-teste-d', N'TST-560673998341', 4, N'alv-teste-18', N'plat-teste-d'),
    -- Ordem E (round-robin por 4 plataformas)
    (N'ps-linha-teste-e1', N'ps-teste-e', N'TST-560673995388', 120, N'alv-teste-19', N'plat-teste-e1'),
    (N'ps-linha-teste-e2', N'ps-teste-e', N'TST-560673995382', 180, N'alv-teste-20', N'plat-teste-e2'),
    (N'ps-linha-teste-e3', N'ps-teste-e', N'TST-560673995392', 174, N'alv-teste-21', N'plat-teste-e3'),
    (N'ps-linha-teste-e4', N'ps-teste-e', N'TST-560673995480', 204, N'alv-teste-22', N'plat-teste-e4'),
    (N'ps-linha-teste-e5', N'ps-teste-e', N'TST-560673995483', 180, N'alv-teste-23', N'plat-teste-e1'),
    (N'ps-linha-teste-e6', N'ps-teste-e', N'TST-560673995486', 204, N'alv-teste-24', N'plat-teste-e2')
) AS novo (Id, OrdemSeparacaoId, Sku, Quantidade, AlveoloId, PlataformaId)
ON alvo.Id = novo.Id
WHEN NOT MATCHED THEN
    INSERT (Id, OrdemSeparacaoId, Sku, Quantidade, AlveoloId, PlataformaId)
    VALUES (novo.Id, novo.OrdemSeparacaoId, novo.Sku, novo.Quantidade, novo.AlveoloId, novo.PlataformaId);
GO

-------------------------------------------------------------------------
-- Missões de picking -- Estado "Criada" de propósito: o pda atribui-as
-- sozinho por ordem de criação (ADR-016/008). PlataformaConfirmada fica
-- no valor por omissão (0/false) -- o gate de montagem (ADR-029) é
-- sempre o primeiro ecrã de cada uma.
-------------------------------------------------------------------------

MERGE dbo.missao AS alvo
USING (VALUES
    (N'missao-teste-a',  N'M-TESTE-A',  N'plat-teste-a'),
    (N'missao-teste-b',  N'M-TESTE-B',  N'plat-teste-b'),
    (N'missao-teste-c',  N'M-TESTE-C',  N'plat-teste-c'),
    (N'missao-teste-d',  N'M-TESTE-D',  N'plat-teste-d'),
    (N'missao-teste-e1', N'M-TESTE-E1', N'plat-teste-e1'),
    (N'missao-teste-e2', N'M-TESTE-E2', N'plat-teste-e2'),
    (N'missao-teste-e3', N'M-TESTE-E3', N'plat-teste-e3'),
    (N'missao-teste-e4', N'M-TESTE-E4', N'plat-teste-e4')
) AS novo (Id, Codigo, PlataformaId)
ON alvo.Id = novo.Id
WHEN NOT MATCHED THEN
    INSERT (Id, Codigo, CentroTrabalho, ZonaId, PlataformaId, Estado)
    VALUES (novo.Id, novo.Codigo, N'Picking', N'zona-teste-a', novo.PlataformaId, N'Criada');
GO

MERGE dbo.missaolinhas AS alvo
USING (VALUES
    -- Ordem A
    (N'missaolinha-teste-a1', N'missao-teste-a', N'TST-560673995077', N'[TESTE] Copo Água Costa Nova 300ml - Turquesa',      N'560673995077', N'alv-teste-01', N'PLT-TESTE-A', N'P2', 18),
    (N'missaolinha-teste-a2', N'missao-teste-a', N'TST-560673995485', N'[TESTE] Prato Sobremesa Costa Nova 21cm - Turquesa', N'560673995485', N'alv-teste-02', N'PLT-TESTE-A', N'P2', 30),
    (N'missaolinha-teste-a3', N'missao-teste-a', N'TST-560673996105', N'[TESTE] Prato Raso Costa Nova 27cm - Turquesa',      N'560673996105', N'alv-teste-03', N'PLT-TESTE-A', N'P2', 30),
    (N'missaolinha-teste-a4', N'missao-teste-a', N'TST-560673996107', N'[TESTE] Prato Fundo Costa Nova 24cm - Turquesa',     N'560673996107', N'alv-teste-04', N'PLT-TESTE-A', N'P2', 30),
    -- Ordem B
    (N'missaolinha-teste-b1', N'missao-teste-b', N'TST-560673993773', N'[TESTE] Chávena Costa Nova 200ml - Basalto', N'560673993773', N'alv-teste-05', N'PLT-TESTE-B', N'P4', 12),
    (N'missaolinha-teste-b2', N'missao-teste-b', N'TST-560673993777', N'[TESTE] Pires Costa Nova 15cm - Basalto',    N'560673993777', N'alv-teste-06', N'PLT-TESTE-B', N'P4', 12),
    -- Ordem C
    (N'missaolinha-teste-c1', N'missao-teste-c', N'TST-560673998092', N'[TESTE] Taça Molho Costa Nova 8cm - Areia',       N'560673998092', N'alv-teste-07', N'PLT-TESTE-C', N'P4', 6),
    (N'missaolinha-teste-c2', N'missao-teste-c', N'TST-560673998328', N'[TESTE] Terrina Costa Nova 25cm - Areia',         N'560673998328', N'alv-teste-08', N'PLT-TESTE-C', N'P4', 12),
    (N'missaolinha-teste-c3', N'missao-teste-c', N'TST-560673998403', N'[TESTE] Terrina Grande Costa Nova 30cm - Areia',  N'560673998403', N'alv-teste-09', N'PLT-TESTE-C', N'P4', 2),
    (N'missaolinha-teste-c4', N'missao-teste-c', N'TST-560673998404', N'[TESTE] Travessa Oval Costa Nova 40cm - Areia',   N'560673998404', N'alv-teste-10', N'PLT-TESTE-C', N'P4', 2),
    (N'missaolinha-teste-c5', N'missao-teste-c', N'TST-560673998406', N'[TESTE] Saladeira Costa Nova 28cm - Areia',       N'560673998406', N'alv-teste-11', N'PLT-TESTE-C', N'P4', 2),
    -- Ordem D
    (N'missaolinha-teste-d1', N'missao-teste-d', N'TST-560673991108', N'[TESTE] Jarra Costa Nova 30cm - Ocre',                N'560673991108', N'alv-teste-12', N'PLT-TESTE-D', N'P1', 3),
    (N'missaolinha-teste-d2', N'missao-teste-d', N'TST-560673993425', N'[TESTE] Vaso Costa Nova 35cm - Ocre',                 N'560673993425', N'alv-teste-13', N'PLT-TESTE-D', N'P1', 3),
    (N'missaolinha-teste-d3', N'missao-teste-d', N'TST-560673995223', N'[TESTE] Fruteira Costa Nova 32cm - Ocre',             N'560673995223', N'alv-teste-14', N'PLT-TESTE-D', N'P1', 2),
    (N'missaolinha-teste-d4', N'missao-teste-d', N'TST-560673997187', N'[TESTE] Marcador de Lugar Costa Nova - Ocre',        N'560673997187', N'alv-teste-15', N'PLT-TESTE-D', N'P1', 6),
    (N'missaolinha-teste-d5', N'missao-teste-d', N'TST-560673997196', N'[TESTE] Conjunto Sal e Pimenta Costa Nova - Ocre',   N'560673997196', N'alv-teste-16', N'PLT-TESTE-D', N'P1', 6),
    (N'missaolinha-teste-d6', N'missao-teste-d', N'TST-560673998105', N'[TESTE] Centro de Mesa Costa Nova 40cm - Ocre',      N'560673998105', N'alv-teste-17', N'PLT-TESTE-D', N'P1', 2),
    (N'missaolinha-teste-d7', N'missao-teste-d', N'TST-560673998341', N'[TESTE] Bowl Decorativo Costa Nova 45cm - Ocre',     N'560673998341', N'alv-teste-18', N'PLT-TESTE-D', N'P1', 4),
    -- Ordem E (uma linha por missão exceto e1/e2, que têm 2 cada)
    (N'missaolinha-teste-e1', N'missao-teste-e1', N'TST-560673995388', N'[TESTE] Travessa Buffet Costa Nova 45cm - Branco',  N'560673995388', N'alv-teste-19', N'PLT-TESTE-E1', N'P1', 120),
    (N'missaolinha-teste-e2', N'missao-teste-e2', N'TST-560673995382', N'[TESTE] Prato Sobremesa Costa Nova 19cm - Branco', N'560673995382', N'alv-teste-20', N'PLT-TESTE-E2', N'P1', 180),
    (N'missaolinha-teste-e3', N'missao-teste-e3', N'TST-560673995392', N'[TESTE] Prato Raso Costa Nova 26cm - Branco',      N'560673995392', N'alv-teste-21', N'PLT-TESTE-E3', N'P1', 174),
    (N'missaolinha-teste-e4', N'missao-teste-e4', N'TST-560673995480', N'[TESTE] Taça Costa Nova 16cm - Branco',            N'560673995480', N'alv-teste-22', N'PLT-TESTE-E4', N'P1', 204),
    (N'missaolinha-teste-e5', N'missao-teste-e1', N'TST-560673995483', N'[TESTE] Pires Costa Nova 17cm - Branco',           N'560673995483', N'alv-teste-23', N'PLT-TESTE-E1', N'P1', 180),
    (N'missaolinha-teste-e6', N'missao-teste-e2', N'TST-560673995486', N'[TESTE] Chávena Costa Nova 220ml - Branco',        N'560673995486', N'alv-teste-24', N'PLT-TESTE-E2', N'P1', 204)
) AS novo (Id, MissaoId, Sku, Descricao, CodigoBarras, AlveoloId, Plataforma, TipoPlataformaCodigo, QuantidadeAlvo)
ON alvo.Id = novo.Id
WHEN MATCHED THEN
    UPDATE SET Descricao = novo.Descricao, CodigoBarras = novo.CodigoBarras
WHEN NOT MATCHED THEN
    INSERT (Id, MissaoId, Sku, Descricao, CodigoBarras, AlveoloId, Plataforma, TipoPlataformaCodigo, QuantidadeAlvo)
    VALUES (novo.Id, novo.MissaoId, novo.Sku, novo.Descricao, novo.CodigoBarras, novo.AlveoloId, novo.Plataforma, novo.TipoPlataformaCodigo, novo.QuantidadeAlvo);
GO

PRINT 'Dados de teste prontos -- 8 missões de picking (Ordens A-E, Zona de Teste A), todas com plataforma por montar. Matrículas de paletes/cestos pré-carregadas (ADR-035): use TST-PAL-MONT-* e TST-CESTO-* para a montagem, TST-PAL-* (sem MONT) para os picks.';
GO

/*
    Para apagar só os dados de teste mais tarde (sem afetar dados
    reais entretanto recebidos), por esta ordem:

      DELETE FROM dbo.operacoesprocessadas WHERE MissaoLinhaId LIKE N'missaolinha-teste-%';
      DELETE FROM dbo.missaolinhas WHERE Id LIKE N'missaolinha-teste-%';
      DELETE FROM dbo.missao WHERE Id LIKE N'missao-teste-%';
      DELETE FROM dbo.ordensseparacaolinhas WHERE Id LIKE N'ps-linha-teste-%';
      DELETE FROM dbo.sl WHERE PlataformaId LIKE N'plat-teste-%' OR PaleteId LIKE N'palete-teste-%';
      DELETE FROM dbo.plataformacestos WHERE PlataformaId LIKE N'plat-teste-%';
      DELETE FROM dbo.cestoinstancias WHERE Id LIKE N'cesto-teste-%';
      DELETE FROM dbo.ordensseparacao WHERE Id LIKE N'ps-teste-%';
      DELETE FROM dbo.plataformas WHERE Id LIKE N'plat-teste-%';
      DELETE FROM dbo.ordenspreparacao WHERE Id LIKE N'op-teste-%';
      DELETE FROM dbo.sa WHERE AlveoloId LIKE N'alv-teste-%';
      DELETE FROM dbo.paletes WHERE Id LIKE N'palete-teste-%';
      DELETE FROM dbo.artigos WHERE Sku LIKE N'TST-%';
      DELETE FROM dbo.alv WHERE Id LIKE N'alv-teste-%';
      DELETE FROM dbo.zonas WHERE Id = N'zona-teste-a';
*/
