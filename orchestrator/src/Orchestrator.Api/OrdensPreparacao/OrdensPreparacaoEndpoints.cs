using Microsoft.EntityFrameworkCore;
using Orchestrator.Api.Data;
using Orchestrator.Api.Data.Entities;
using Orchestrator.Api.Tipificacao;

namespace Orchestrator.Api.OrdensPreparacao;

/// <summary>
/// "Ordem de preparação" do documento de requisitos v0.4 (ADR-015):
/// agrupa PS por cliente/data/morada (RF-CTL-02), cubica-se, tipifica-se
/// (gera Plataformas, RF-CTL-01/A.4/A.5) e é despachada (ver
/// PlataformasEndpoints). Composição manual pelo supervisor nesta
/// versão — sem proposta automática de agrupamento (fica para além do
/// MVP, ver ARCHITECTURE.md secção 8).
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
            if (pedido.PsIds is not { Count: > 0 })
                return Results.BadRequest(new { erro = "É preciso indicar pelo menos um PS." });

            var ps = await db.OrdensSeparacao.Where(o => pedido.PsIds.Contains(o.Id)).ToListAsync();
            if (ps.Count != pedido.PsIds.Count)
                return Results.BadRequest(new { erro = "Um ou mais PS indicados não existem." });
            if (ps.Any(o => o.OrdemPreparacaoId is not null))
                return Results.Conflict(new { erro = "Um ou mais PS já pertencem a outra Ordem de Preparação." });

            var entidade = new OrdemPreparacaoEntity
            {
                Id = Guid.NewGuid().ToString("n"),
                Cliente = pedido.Cliente,
                DataEntrega = pedido.DataEntrega,
                MoradaEntrega = pedido.MoradaEntrega,
            };
            db.OrdensPreparacao.Add(entidade);

            foreach (var p in ps)
                p.OrdemPreparacaoId = entidade.Id;

            await db.SaveChangesAsync();

            var dto = await ParaResumoAsync(db, entidade.Id, new CubicagemService(db));
            return Results.Created($"/api/ordens-preparacao/{entidade.Id}", dto);
        })
        .WithName("ComporOrdemPreparacao");

        group.MapGet("/", async (WopaDbContext db, CubicagemService cubicagem) =>
        {
            var ids = await db.OrdensPreparacao.OrderByDescending(o => o.CriadaEm).Select(o => o.Id).ToListAsync();
            var resultado = new List<OrdemPreparacaoResumo>();
            foreach (var id in ids)
            {
                var dto = await ParaResumoAsync(db, id, cubicagem);
                if (dto is not null) resultado.Add(dto);
            }
            return resultado;
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

            var resultadoCubicagem = await cubicagem.CubicarOrdemAsync(todasLinhas);
            var tipo = await cubicagem.TipificarAsync(resultadoCubicagem.VolumeCm3);
            if (tipo.TipoCodigo is null)
                return Results.Conflict(new { erro = "Volume de picking nulo — a ordem não pode ser tipificada (verificar fichas de artigo incompletas)." });

            // Remove plataformas anteriores desta ordem, caso já tivesse sido tipificada.
            var plataformasAntigas = await db.Plataformas.Where(p => p.OrdemPreparacaoId == id).ToListAsync();
            if (plataformasAntigas.Count > 0)
            {
                foreach (var linha in todasLinhas) linha.PlataformaId = null;
                db.Plataformas.RemoveRange(plataformasAntigas);
            }

            var camadas = CubicagemService.SequenciaCamadas(tipo.NPlataformas, ordem.AlturaPaleteCm);
            var novasPlataformas = camadas.Select((c, i) => new PlataformaEntity
            {
                Id = Guid.NewGuid().ToString("n"),
                Codigo = $"PLT-{Random.Shared.Next(1000, 9999)}-{i + 1}",
                OrdemPreparacaoId = ordem.Id,
                TipoPlataformaCodigo = tipo.TipoCodigo,
                IndiceCamada = tipo.NPlataformas > 1 ? c.Indice : null,
                ClasseCamada = tipo.NPlataformas > 1 ? c.Classe : null,
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
    }

    private static async Task<OrdemPreparacaoResumo?> ParaResumoAsync(WopaDbContext db, string id, CubicagemService cubicagem)
    {
        var ordem = await db.OrdensPreparacao
            .Include(o => o.Ps).ThenInclude(p => p.Linhas)
            .Include(o => o.Plataformas)
            .SingleOrDefaultAsync(o => o.Id == id);
        if (ordem is null) return null;

        var todasLinhas = ordem.Ps.SelectMany(p => p.Linhas).ToList();
        decimal? volumeLitros = null;
        decimal? pesoKg = null;
        string? tipoIndicativo = null;
        if (todasLinhas.Count > 0)
        {
            var resultado = await cubicagem.CubicarOrdemAsync(todasLinhas);
            var tipo = await cubicagem.TipificarAsync(resultado.VolumeCm3);
            volumeLitros = resultado.VolumeLitros;
            pesoKg = resultado.PesoKg;
            tipoIndicativo = tipo.Notacao;
        }

        return new OrdemPreparacaoResumo(
            ordem.Id, ordem.Cliente, ordem.DataEntrega, ordem.MoradaEntrega, ordem.Estado, ordem.AlturaPaleteCm,
            ordem.CriadaEm, ordem.Ps.Count, volumeLitros, pesoKg, tipoIndicativo,
            ordem.Plataformas.Select(p => new PlataformaResumo(p.Id, p.Codigo, p.TipoPlataformaCodigo, p.IndiceCamada, p.ClasseCamada, p.Estado, p.CelulaDestino)).ToList());
    }
}
