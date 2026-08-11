using Microsoft.EntityFrameworkCore;
using Orchestrator.Api.Data;
using Orchestrator.Api.Data.Entities;
using Orchestrator.Api.Tipificacao;

namespace Orchestrator.Api.OrdensPreparacao;

/// <summary>
/// "Ordem de preparação" do documento de requisitos v0.4 (ADR-017):
/// chega já composta de outro software — agrupamento de PS por
/// cliente/data/morada já feito lá. O WOPA só a recebe e guarda
/// (POST); a partir daí é que trata das etapas seguintes: cubica-se,
/// tipifica-se (gera Plataformas, RF-CTL-01/A.4/A.5) e é despachada
/// (ver PlataformasEndpoints). Não existe fluxo de composição manual
/// no WOPA.
/// </summary>
public static class OrdensPreparacaoEndpoints
{
    public static void MapOrdensPreparacaoEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/ordens-preparacao").WithTags("OrdensPreparacao");

        group.MapPost("/", async (NovaOrdemPreparacaoRequest pedido, WopaDbContext db) =>
        {
            if (string.IsNullOrWhiteSpace(pedido.Cliente))
                return Results.BadRequest(new { erro = "cliente é obrigatório." });
            if (pedido.Ps is not { Count: > 0 })
                return Results.BadRequest(new { erro = "A ordem de preparação tem de ter pelo menos um PS." });
            foreach (var ps in pedido.Ps)
            {
                if (string.IsNullOrWhiteSpace(ps.NumeroDocumento))
                    return Results.BadRequest(new { erro = "Todos os PS têm de ter numeroDocumento." });
                if (string.IsNullOrWhiteSpace(ps.Origem))
                    return Results.BadRequest(new { erro = "Todos os PS têm de ter origem." });
                if (ps.Linhas is not { Count: > 0 })
                    return Results.BadRequest(new { erro = $"O PS {ps.NumeroDocumento} tem de ter pelo menos uma linha." });
                if (ps.Linhas.Any(l => l.Quantidade <= 0))
                    return Results.BadRequest(new { erro = $"Todas as linhas do PS {ps.NumeroDocumento} têm de ter quantidade maior que zero." });
            }

            // AlveoloCodigo é opcional (nem toda origem o vai ter disponível —
            // ADR-011); resolve-se para AlveoloId quando existir e for
            // reconhecido, sem bloquear a receção se não for.
            var codigosDados = pedido.Ps
                .SelectMany(ps => ps.Linhas)
                .Where(l => l.AlveoloCodigo is not null)
                .Select(l => l.AlveoloCodigo!)
                .Distinct()
                .ToList();
            var alveolosPorCodigo = await db.Alveolos
                .Where(a => codigosDados.Contains(a.Codigo))
                .ToDictionaryAsync(a => a.Codigo, a => a.Id);

            var ordem = new OrdemPreparacaoEntity
            {
                Id = Guid.NewGuid().ToString("n"),
                Cliente = pedido.Cliente,
                DataEntrega = pedido.DataEntrega,
                MoradaEntrega = pedido.MoradaEntrega,
                ReferenciaExterna = pedido.ReferenciaExterna,
                NumeroOrdem = pedido.NumeroOrdem,
                NumeroPedido = pedido.NumeroPedido,
                NumeroCliente = pedido.NumeroCliente,
                TipoPlataformaCodigo = pedido.TipoPlataformaCodigo,
                NPlataformas = pedido.NPlataformas,
                NumRefs = pedido.NumRefs,
                TotalCaixas = pedido.TotalCaixas,
                VolumeTotalCm3 = pedido.VolumeTotalCm3,
                PesoTotalKg = pedido.PesoTotalKg,
                RefsSemFicha = pedido.RefsSemFicha,
                Observacoes = pedido.Observacoes,
            };
            db.OrdensPreparacao.Add(ordem);

            foreach (var ps in pedido.Ps)
            {
                db.OrdensSeparacao.Add(new OrdemSeparacaoEntity
                {
                    Id = Guid.NewGuid().ToString("n"),
                    OrdemPreparacaoId = ordem.Id,
                    NumeroDocumento = ps.NumeroDocumento,
                    Origem = ps.Origem,
                    Canal = ps.Canal,
                    Linhas = ps.Linhas.Select(l => new OrdemSeparacaoLinhaEntity
                    {
                        Id = Guid.NewGuid().ToString("n"),
                        Sku = l.Sku,
                        Quantidade = l.Quantidade,
                        AlveoloId = l.AlveoloCodigo is { } codigo && alveolosPorCodigo.TryGetValue(codigo, out var alveoloId)
                            ? alveoloId
                            : null,
                    }).ToList(),
                });
            }

            await db.SaveChangesAsync();

            var dto = await ParaResumoAsync(db, ordem.Id, new CubicagemService(db));
            return Results.Created($"/api/ordens-preparacao/{ordem.Id}", dto);
        })
        .WithName("ReceberOrdemPreparacao");

        // Lista todas as ordens numa só passagem: carrega Artigos e
        // TiposPlataforma UMA vez (em vez de por ordem) e cubica/tipifica
        // em memória — com volumes reais (milhares de ordens, ver
        // ARCHITECTURE.md ADR-019) uma consulta por ordem tornava isto
        // lento a sério (~15s para 2500 ordens); esta versão faz o mesmo
        // em poucas centenas de ms.
        group.MapGet("/", async (WopaDbContext db) =>
        {
            // AsSplitQuery: duas coleções irmãs (Ps.Linhas e Plataformas)
            // numa só query com JOIN multiplicavam linhas desnecessariamente
            // (produto cartesiano) — consultas separadas para cada coleção
            // são mais rápidas aqui, mesmo sendo mais round-trips.
            var ordens = await db.OrdensPreparacao
                .AsSplitQuery()
                .Include(o => o.Ps).ThenInclude(p => p.Linhas)
                .Include(o => o.Plataformas)
                .OrderByDescending(o => o.RecebidaEm)
                .ToListAsync();

            var todosSkus = ordens.SelectMany(o => o.Ps.SelectMany(p => p.Linhas)).Select(l => l.Sku).Distinct().ToList();
            var artigos = await db.Artigos.Where(a => todosSkus.Contains(a.Sku)).ToDictionaryAsync(a => a.Sku);
            var tipos = await db.TiposPlataforma.OrderBy(t => t.CapacidadeUtilLitros).ToListAsync();

            return ordens.Select(o => ParaResumo(o, artigos, tipos)).ToList();
        })
        .WithName("ListarOrdensPreparacao");

        group.MapGet("/{id}", async (string id, WopaDbContext db, CubicagemService cubicagem) =>
        {
            var dto = await ParaResumoAsync(db, id, cubicagem);
            return dto is not null ? Results.Ok(dto) : Results.NotFound();
        })
        .WithName("ObterOrdemPreparacao");

        // Anexo A.2/A.4/A.5/A.8: cubica as linhas de todos os PS da ordem,
        // escolhe o tipo (ou decompõe em multi-plataforma) e gera as
        // Plataformas com o respetivo índice de camada. As linhas de PS são
        // distribuídas pelas plataformas geradas por round-robin — o
        // critério real por camada/volume ainda é uma decisão pendente do
        // próprio documento v0.4 (A.5), ver ARCHITECTURE.md secção 8.
        group.MapPost("/{id}/tipificar", async (string id, TipificarRequest pedido, WopaDbContext db, CubicagemService cubicagem) =>
        {
            var ordem = await db.OrdensPreparacao
                .Include(o => o.Ps).ThenInclude(p => p.Linhas)
                .SingleOrDefaultAsync(o => o.Id == id);
            if (ordem is null) return Results.NotFound();

            if (pedido.AlturaPaleteCm is { } altura)
                ordem.AlturaPaleteCm = altura;

            var todasLinhas = ordem.Ps.SelectMany(p => p.Linhas).ToList();
            if (todasLinhas.Count == 0)
                return Results.Conflict(new { erro = "A ordem de preparação não tem linhas para tipificar." });

            // ADR-032: quando a origem (query real de tipificação do PHC) já
            // decidiu o tipo de plataforma, materializa-se diretamente em vez
            // de recalcular por cubicagem -- evita divergir da decisão do
            // cliente. Sem isso (ordens antigas/de teste), mantém-se a
            // cubicagem do próprio WOPA como estava.
            string tipoCodigo;
            int nPlataformas;
            if (ordem.TipoPlataformaCodigo is { } tipoOrigem)
            {
                tipoCodigo = tipoOrigem;
                nPlataformas = ordem.NPlataformas is > 0 ? ordem.NPlataformas.Value : 1;
            }
            else
            {
                var resultadoCubicagem = await cubicagem.CubicarOrdemAsync(todasLinhas);
                var tipo = await cubicagem.TipificarAsync(resultadoCubicagem.VolumeCm3);
                if (tipo.TipoCodigo is null)
                    return Results.Conflict(new { erro = "Volume de picking nulo — a ordem não pode ser tipificada (verificar fichas de artigo incompletas)." });
                tipoCodigo = tipo.TipoCodigo;
                nPlataformas = tipo.NPlataformas;
            }

            // Remove plataformas anteriores desta ordem, caso já tivesse sido tipificada.
            var plataformasAntigas = await db.Plataformas.Where(p => p.OrdemPreparacaoId == id).ToListAsync();
            if (plataformasAntigas.Count > 0)
            {
                foreach (var linha in todasLinhas) linha.PlataformaId = null;
                db.Plataformas.RemoveRange(plataformasAntigas);
            }

            var camadas = CubicagemService.SequenciaCamadas(nPlataformas, ordem.AlturaPaleteCm);
            var novasPlataformas = camadas.Select((c, i) => new PlataformaEntity
            {
                Id = Guid.NewGuid().ToString("n"),
                Codigo = $"PLT-{Random.Shared.Next(1000, 9999)}-{i + 1}",
                OrdemPreparacaoId = ordem.Id,
                TipoPlataformaCodigo = tipoCodigo,
                IndiceCamada = nPlataformas > 1 ? c.Indice : null,
                ClasseCamada = nPlataformas > 1 ? c.Classe : null,
                Estado = "EmPicking",
            }).ToList();
            db.Plataformas.AddRange(novasPlataformas);

            for (var i = 0; i < todasLinhas.Count; i++)
                todasLinhas[i].PlataformaId = novasPlataformas[i % novasPlataformas.Count].Id;

            ordem.Estado = "Tipificada";
            await db.SaveChangesAsync();

            var dto = await ParaResumoAsync(db, id, cubicagem);
            return Results.Ok(dto);
        })
        .WithName("TipificarOrdemPreparacao");

        // ADR-027: etiqueta de urgência do controller (não vem da origem) --
        // permite ao supervisor marcar uma ordem para subir na fila, com
        // data limite opcional.
        group.MapPost("/{id}/urgente", async (string id, UrgenteRequest pedido, WopaDbContext db, CubicagemService cubicagem) =>
        {
            var ordem = await db.OrdensPreparacao.SingleOrDefaultAsync(o => o.Id == id);
            if (ordem is null) return Results.NotFound();

            ordem.Urgente = pedido.Urgente;
            ordem.DataLimite = pedido.DataLimite;
            await db.SaveChangesAsync();

            var dto = await ParaResumoAsync(db, id, cubicagem);
            return Results.Ok(dto);
        })
        .WithName("MarcarOrdemPreparacaoUrgente");
    }

    private static async Task<OrdemPreparacaoResumo?> ParaResumoAsync(WopaDbContext db, string id, CubicagemService cubicagem)
    {
        var ordem = await db.OrdensPreparacao
            .Include(o => o.Ps).ThenInclude(p => p.Linhas)
            .Include(o => o.Plataformas)
            .SingleOrDefaultAsync(o => o.Id == id);
        if (ordem is null) return null;

        var skus = ordem.Ps.SelectMany(p => p.Linhas).Select(l => l.Sku).Distinct().ToList();
        var artigos = await db.Artigos.Where(a => skus.Contains(a.Sku)).ToDictionaryAsync(a => a.Sku);
        var tipos = await cubicagem.TiposPlataformaOrdenadosAsync();
        return ParaResumo(ordem, artigos, tipos);
    }

    private static OrdemPreparacaoResumo ParaResumo(
        OrdemPreparacaoEntity ordem,
        IReadOnlyDictionary<string, ArtigoEntity> artigosPorSku,
        IReadOnlyList<TipoPlataformaEntity> tiposOrdenados)
    {
        var todasLinhas = ordem.Ps.SelectMany(p => p.Linhas).ToList();
        decimal? volumeLitros = null;
        decimal? pesoKg = null;
        string? tipoIndicativo = null;
        if (todasLinhas.Count > 0)
        {
            var resultado = CubicagemService.CubicarOrdem(todasLinhas, artigosPorSku);
            var tipo = CubicagemService.Tipificar(resultado.VolumeCm3, tiposOrdenados);
            volumeLitros = resultado.VolumeLitros;
            pesoKg = resultado.PesoKg;
            tipoIndicativo = tipo.Notacao;
        }

        return new OrdemPreparacaoResumo(
            ordem.Id, ordem.Cliente, ordem.DataEntrega, ordem.MoradaEntrega, ordem.Estado, ordem.AlturaPaleteCm,
            ordem.RecebidaEm, ordem.Ps.Count, volumeLitros, pesoKg, tipoIndicativo,
            ordem.Plataformas.Select(p => new PlataformaResumo(p.Id, p.Codigo, p.TipoPlataformaCodigo, p.IndiceCamada, p.ClasseCamada, p.Estado, p.CelulaDestino)).ToList(),
            ordem.Urgente, ordem.DataLimite,
            ordem.ReferenciaExterna, ordem.NumeroOrdem, ordem.NumeroPedido,
            ordem.TipoPlataformaCodigo, ordem.NPlataformas, ordem.RefsSemFicha, ordem.Observacoes);
    }
}
