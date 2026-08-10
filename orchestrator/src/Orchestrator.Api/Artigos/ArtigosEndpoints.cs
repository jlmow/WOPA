using Microsoft.EntityFrameworkCore;
using Orchestrator.Api.Data;
using Orchestrator.Api.Data.Entities;

namespace Orchestrator.Api.Artigos;

public record ArtigoDto(
    string Sku,
    string? Ean,
    string Descricao,
    int? UnidadesPorCaixa,
    decimal? ComprimentoCaixaCm,
    decimal? LarguraCaixaCm,
    decimal? AlturaCaixaCm,
    decimal? PesoUnitarioKg,
    string? ClasseEmpilhamento,
    int? CaixasPorPaleteCompleta);

/// <summary>
/// Dados mestre de artigo (RF-ENT-03) — recebidos via integração com o
/// ERP, tal como os PS. Base da cubicagem (Anexo A.1) e da deteção de
/// ficha incompleta (RF-ENT-04/A.6).
/// </summary>
public static class ArtigosEndpoints
{
    public static void MapArtigosEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/artigos").WithTags("Artigos");

        // Upsert em lote — a integração real pode reenviar a mesma
        // referência com dados atualizados sem que isso seja um erro.
        group.MapPost("/", async (IReadOnlyList<ArtigoDto> artigos, WopaDbContext db) =>
        {
            if (artigos is not { Count: > 0 })
                return Results.BadRequest(new { erro = "É preciso enviar pelo menos um artigo." });

            var skus = artigos.Select(a => a.Sku).ToList();
            var existentes = await db.Artigos.Where(a => skus.Contains(a.Sku)).ToDictionaryAsync(a => a.Sku);

            foreach (var artigo in artigos)
            {
                if (existentes.TryGetValue(artigo.Sku, out var entidade))
                {
                    Aplicar(entidade, artigo);
                }
                else
                {
                    entidade = new ArtigoEntity { Sku = artigo.Sku };
                    Aplicar(entidade, artigo);
                    db.Artigos.Add(entidade);
                }
            }

            await db.SaveChangesAsync();
            return Results.Ok(new { atualizados = artigos.Count });
        })
        .WithName("ReceberArtigos");

        group.MapGet("/", async (WopaDbContext db) =>
        {
            var artigos = await db.Artigos.OrderBy(a => a.Sku).ToListAsync();
            return artigos.Select(ParaDto);
        })
        .WithName("ListarArtigos");
    }

    private static void Aplicar(ArtigoEntity entidade, ArtigoDto dto)
    {
        entidade.Ean = dto.Ean;
        entidade.Descricao = dto.Descricao;
        entidade.UnidadesPorCaixa = dto.UnidadesPorCaixa;
        entidade.ComprimentoCaixaCm = dto.ComprimentoCaixaCm;
        entidade.LarguraCaixaCm = dto.LarguraCaixaCm;
        entidade.AlturaCaixaCm = dto.AlturaCaixaCm;
        entidade.PesoUnitarioKg = dto.PesoUnitarioKg;
        entidade.ClasseEmpilhamento = dto.ClasseEmpilhamento;
        entidade.CaixasPorPaleteCompleta = dto.CaixasPorPaleteCompleta;
    }

    private static ArtigoDto ParaDto(ArtigoEntity a) => new(
        a.Sku, a.Ean, a.Descricao, a.UnidadesPorCaixa, a.ComprimentoCaixaCm, a.LarguraCaixaCm,
        a.AlturaCaixaCm, a.PesoUnitarioKg, a.ClasseEmpilhamento, a.CaixasPorPaleteCompleta);
}
