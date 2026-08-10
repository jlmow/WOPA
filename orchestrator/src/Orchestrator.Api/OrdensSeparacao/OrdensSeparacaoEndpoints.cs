using Microsoft.EntityFrameworkCore;
using Orchestrator.Api.Data;
using Orchestrator.Api.Data.Entities;
using Orchestrator.Api.Tipificacao;

namespace Orchestrator.Api.OrdensSeparacao;

public static class OrdensSeparacaoEndpoints
{
    public static void MapOrdensSeparacaoEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/ordens-separacao").WithTags("OrdensSeparacao");

        // Independente da origem (PHC ou OrdersHub — ADR-008), é aqui que a
        // informação entra no WOPA. O trabalho do controller (agrupar PS em
        // Ordens de Preparação, RF-CTL-02) começa a partir do que ficar
        // guardado aqui.
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
                Cliente = pedido.Cliente,
                DataEntrega = pedido.DataEntrega,
                MoradaEntrega = pedido.MoradaEntrega,
                Canal = pedido.Canal,
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

            var resposta = await ParaDto(db, entidade.Id, comCubicagem: false);
            return Results.Created($"/api/ordens-separacao/{entidade.Id}", resposta);
        })
        .WithName("ReceberOrdemSeparacao");

        // RF-CTL-01: PS abertos (ainda não agrupados numa Ordem de
        // Preparação) com cubicagem e tipificação indicativa.
        group.MapGet("/", async (bool? abertas, WopaDbContext db, CubicagemService cubicagem) =>
        {
            var query = db.OrdensSeparacao
                .Include(o => o.Linhas).ThenInclude(l => l.Alveolo)
                .AsQueryable();

            if (abertas == true)
                query = query.Where(o => o.OrdemPreparacaoId == null);

            var ordens = await query.OrderByDescending(o => o.RecebidaEm).ToListAsync();

            var resultado = new List<OrdemSeparacao>();
            foreach (var ordem in ordens)
            {
                var dto = ParaDto(ordem);
                dto.Cubicagem = await CalcularCubicagemIndicativaAsync(cubicagem, ordem.Linhas);
                resultado.Add(dto);
            }
            return resultado;
        })
        .WithName("ListarOrdensSeparacao");

        group.MapGet("/{id}", async (string id, WopaDbContext db, CubicagemService cubicagem) =>
        {
            var dto = await ParaDto(db, id, comCubicagem: true, cubicagem);
            return dto is not null ? Results.Ok(dto) : Results.NotFound();
        })
        .WithName("ObterOrdemSeparacao");
    }

    private static async Task<CubicagemIndicativa> CalcularCubicagemIndicativaAsync(
        CubicagemService cubicagem, IReadOnlyList<OrdemSeparacaoLinhaEntity> linhas)
    {
        var resultado = await cubicagem.CubicarOrdemAsync(linhas);
        var tipo = await cubicagem.TipificarAsync(resultado.VolumeCm3);
        return new CubicagemIndicativa(resultado.VolumeLitros, resultado.PesoKg, resultado.NRefs, resultado.NLinhasNaoCubicaveis, tipo.Notacao);
    }

    private static async Task<OrdemSeparacao?> ParaDto(WopaDbContext db, string id, bool comCubicagem, CubicagemService? cubicagem = null)
    {
        var ordem = await db.OrdensSeparacao
            .Include(o => o.Linhas).ThenInclude(l => l.Alveolo)
            .SingleOrDefaultAsync(o => o.Id == id);
        if (ordem is null) return null;

        var dto = ParaDto(ordem);
        if (comCubicagem && cubicagem is not null)
            dto.Cubicagem = await CalcularCubicagemIndicativaAsync(cubicagem, ordem.Linhas);
        return dto;
    }

    private static OrdemSeparacao ParaDto(OrdemSeparacaoEntity ordem) => new()
    {
        Id = ordem.Id,
        NumeroDocumento = ordem.NumeroDocumento,
        Origem = ordem.Origem,
        RecebidaEm = ordem.RecebidaEm,
        Processada = ordem.Processada,
        Cliente = ordem.Cliente,
        DataEntrega = ordem.DataEntrega,
        MoradaEntrega = ordem.MoradaEntrega,
        Canal = ordem.Canal,
        OrdemPreparacaoId = ordem.OrdemPreparacaoId,
        Linhas = ordem.Linhas
            .Select(l => new OrdemSeparacaoLinha(l.Sku, l.Quantidade, l.Alveolo?.Codigo))
            .ToList(),
    };
}
