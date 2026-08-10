namespace Orchestrator.Api.OrdensSeparacao;

public static class OrdensSeparacaoEndpoints
{
    public static void MapOrdensSeparacaoEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/ordens-separacao").WithTags("OrdensSeparacao");

        // Independente da origem (PHC ou OrdersHub — ADR-008), é aqui que a
        // informação entra no WOPA. O trabalho do controller (criar missões)
        // começa a partir do que ficar guardado aqui.
        group.MapPost("/", (NovaOrdemSeparacaoRequest pedido, OrdensSeparacaoStore store) =>
        {
            if (string.IsNullOrWhiteSpace(pedido.NumeroDocumento))
                return Results.BadRequest(new { erro = "numeroDocumento é obrigatório." });

            if (string.IsNullOrWhiteSpace(pedido.Origem))
                return Results.BadRequest(new { erro = "origem é obrigatório." });

            if (pedido.Linhas is not { Count: > 0 })
                return Results.BadRequest(new { erro = "A ordem de separação tem de ter pelo menos uma linha." });

            if (pedido.Linhas.Any(l => l.Quantidade <= 0))
                return Results.BadRequest(new { erro = "Todas as linhas têm de ter quantidade maior que zero." });

            var ordem = store.Adicionar(pedido);
            return Results.Created($"/api/ordens-separacao/{ordem.Id}", ordem);
        })
        .WithName("ReceberOrdemSeparacao");

        group.MapGet("/", (OrdensSeparacaoStore store) => store.GetAll())
            .WithName("ListarOrdensSeparacao");

        group.MapGet("/{id}", (string id, OrdensSeparacaoStore store) =>
            store.Get(id) is { } ordem ? Results.Ok(ordem) : Results.NotFound())
            .WithName("ObterOrdemSeparacao");
    }
}
