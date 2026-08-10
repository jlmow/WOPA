using Microsoft.EntityFrameworkCore;
using Orchestrator.Api.Data;
using Orchestrator.Api.Data.Entities;

namespace Orchestrator.Api.OrdensSeparacao;

public static class OrdensSeparacaoEndpoints
{
    public static void MapOrdensSeparacaoEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/ordens-separacao").WithTags("OrdensSeparacao");

        // Independente da origem (PHC ou OrdersHub — ADR-008), é aqui que a
        // informação entra no WOPA. O trabalho do controller (criar missões)
        // começa a partir do que ficar guardado aqui.
        group.MapPost("/", async (NovaOrdemSeparacaoRequest pedido, WopaDbContext db) =>
        {
            if (string.IsNullOrWhiteSpace(pedido.NumeroDocumento))
                return Results.BadRequest(new { erro = "numeroDocumento é obrigatório." });

            if (string.IsNullOrWhiteSpace(pedido.Origem))
                return Results.BadRequest(new { erro = "origem é obrigatório." });

            if (pedido.Linhas is not { Count: > 0 })
                return Results.BadRequest(new { erro = "A ordem de separação tem de ter pelo menos uma linha." });

            if (pedido.Linhas.Any(l => l.Quantidade <= 0))
                return Results.BadRequest(new { erro = "Todas as linhas têm de ter quantidade maior que zero." });

            // AlveoloCodigo é opcional (nem toda origem o vai ter disponível —
            // ADR-011); resolve-se para AlveoloId quando existir e for
            // reconhecido, sem bloquear a receção se não for.
            var codigosDados = pedido.Linhas
                .Where(l => l.AlveoloCodigo is not null)
                .Select(l => l.AlveoloCodigo!)
                .Distinct()
                .ToList();
            var alveolosPorCodigo = await db.Alveolos
                .Where(a => codigosDados.Contains(a.Codigo))
                .ToDictionaryAsync(a => a.Codigo, a => a.Id);

            var entidade = new OrdemSeparacaoEntity
            {
                Id = Guid.NewGuid().ToString("n"),
                NumeroDocumento = pedido.NumeroDocumento,
                Origem = pedido.Origem,
                Linhas = pedido.Linhas.Select(l => new OrdemSeparacaoLinhaEntity
                {
                    Id = Guid.NewGuid().ToString("n"),
                    Sku = l.Sku,
                    Quantidade = l.Quantidade,
                    AlveoloId = l.AlveoloCodigo is { } codigo && alveolosPorCodigo.TryGetValue(codigo, out var alveoloId)
                        ? alveoloId
                        : null,
                }).ToList(),
            };

            db.OrdensSeparacao.Add(entidade);
            await db.SaveChangesAsync();

            var resposta = await ParaDto(db, entidade.Id);
            return Results.Created($"/api/ordens-separacao/{entidade.Id}", resposta);
        })
        .WithName("ReceberOrdemSeparacao");

        group.MapGet("/", async (WopaDbContext db) =>
        {
            var ordens = await db.OrdensSeparacao
                .Include(o => o.Linhas).ThenInclude(l => l.Alveolo)
                .OrderByDescending(o => o.RecebidaEm)
                .ToListAsync();
            return ordens.Select(ParaDto);
        })
        .WithName("ListarOrdensSeparacao");

        group.MapGet("/{id}", async (string id, WopaDbContext db) =>
        {
            var dto = await ParaDto(db, id);
            return dto is not null ? Results.Ok(dto) : Results.NotFound();
        })
        .WithName("ObterOrdemSeparacao");
    }

    private static async Task<OrdemSeparacao?> ParaDto(WopaDbContext db, string id)
    {
        var ordem = await db.OrdensSeparacao
            .Include(o => o.Linhas).ThenInclude(l => l.Alveolo)
            .SingleOrDefaultAsync(o => o.Id == id);
        return ordem is null ? null : ParaDto(ordem);
    }

    private static OrdemSeparacao ParaDto(OrdemSeparacaoEntity ordem) => new()
    {
        Id = ordem.Id,
        NumeroDocumento = ordem.NumeroDocumento,
        Origem = ordem.Origem,
        RecebidaEm = ordem.RecebidaEm,
        Processada = ordem.Processada,
        Linhas = ordem.Linhas
            .Select(l => new OrdemSeparacaoLinha(l.Sku, l.Quantidade, l.Alveolo?.Codigo))
            .ToList(),
    };
}
