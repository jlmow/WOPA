using Microsoft.EntityFrameworkCore;
using Orchestrator.Api.Data;
using Orchestrator.Api.Data.Entities;
using Orchestrator.Api.Picking;

namespace Orchestrator.Api.Plataformas;

/// <summary>
/// Plataformas geradas pela tipificação de uma Ordem de Preparação
/// (ver OrdensPreparacaoEndpoints). "Despachar" (RF-CTL-06) atribui uma
/// célula e gera a Missão de picking correspondente (RF-PIC-01) — só
/// nesse momento é que o `pda` passa a ter trabalho para executar.
/// </summary>
public static class PlataformasEndpoints
{
    public static void MapPlataformasEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/plataformas").WithTags("Plataformas");

        group.MapGet("/", async (WopaDbContext db) =>
        {
            var plataformas = await db.Plataformas
                .Include(p => p.TipoPlataforma)
                .OrderByDescending(p => p.CriadaEm)
                .ToListAsync();

            var ordemPreparacaoIds = plataformas.Where(p => p.OrdemPreparacaoId is not null).Select(p => p.OrdemPreparacaoId!).Distinct().ToList();
            var clientesPorOrdem = await db.OrdensPreparacao
                .Where(o => ordemPreparacaoIds.Contains(o.Id))
                .ToDictionaryAsync(o => o.Id, o => o.Cliente);

            var missaoPorPlataforma = await db.Missoes
                .Where(m => m.PlataformaId != null)
                .ToDictionaryAsync(m => m.PlataformaId!, m => m.Id);

            return plataformas.Select(p => ParaDto(p, clientesPorOrdem, missaoPorPlataforma));
        })
        .WithName("ListarPlataformas");

        group.MapPost("/{id}/despachar", async (string id, DespacharRequest pedido, WopaDbContext db) =>
        {
            var plataforma = await db.Plataformas.SingleOrDefaultAsync(p => p.Id == id);
            if (plataforma is null) return Results.NotFound();

            if (await db.Missoes.AnyAsync(m => m.PlataformaId == id))
                return Results.Conflict(new { erro = "Esta plataforma já tem uma missão de picking associada." });

            var linhasPs = await db.OrdensSeparacaoLinhas
                .Include(l => l.Alveolo)
                .Where(l => l.PlataformaId == id)
                .ToListAsync();
            if (linhasPs.Count == 0)
                return Results.Conflict(new { erro = "Esta plataforma não tem linhas atribuídas." });

            var skus = linhasPs.Select(l => l.Sku).Distinct().ToList();
            var artigos = await db.Artigos.Where(a => skus.Contains(a.Sku)).ToDictionaryAsync(a => a.Sku);

            if (pedido.CelulaDestino is not null)
                plataforma.CelulaDestino = pedido.CelulaDestino;

            var zonaId = linhasPs.Select(l => l.Alveolo?.ZonaId).FirstOrDefault(z => z is not null);

            var missao = new MissaoEntity
            {
                Id = Guid.NewGuid().ToString("n"),
                Codigo = $"M-{plataforma.Codigo}",
                ZonaId = zonaId,
                CentroTrabalho = "Picking",
                Estado = "Criada",
                PlataformaId = plataforma.Id,
                Linhas = linhasPs.Select(l =>
                {
                    var artigo = artigos.GetValueOrDefault(l.Sku);
                    return new MissaoLinhaEntity
                    {
                        Id = Guid.NewGuid().ToString("n"),
                        Sku = l.Sku,
                        Descricao = artigo?.Descricao ?? l.Sku,
                        CodigoBarras = artigo?.Ean ?? l.Sku,
                        AlveoloId = l.AlveoloId,
                        Plataforma = plataforma.Codigo,
                        TipoPlataformaCodigo = plataforma.TipoPlataformaCodigo,
                        QuantidadeAlvo = l.Quantidade,
                        Estado = PickingTaskStatus.Pendente,
                    };
                }).ToList(),
            };

            db.Missoes.Add(missao);
            await db.SaveChangesAsync();

            return Results.Ok(new { missaoId = missao.Id });
        })
        .WithName("DespacharPlataforma");
    }

    private static PlataformaDto ParaDto(
        PlataformaEntity p,
        IReadOnlyDictionary<string, string> clientesPorOrdem,
        IReadOnlyDictionary<string, string> missaoPorPlataforma) => new(
        p.Id,
        p.Codigo,
        p.OrdemPreparacaoId,
        p.OrdemPreparacaoId is { } opId && clientesPorOrdem.TryGetValue(opId, out var cliente) ? cliente : null,
        p.TipoPlataformaCodigo,
        p.IndiceCamada,
        p.ClasseCamada,
        p.CelulaDestino,
        p.Estado,
        missaoPorPlataforma.GetValueOrDefault(p.Id));
}
