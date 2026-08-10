namespace Orchestrator.Api.Config;

public static class RegrasMissaoEndpoints
{
    public static void MapRegrasMissaoEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/config/regras-missao").WithTags("Config");

        group.MapGet("/", (RegrasMissaoStore store) => store.Obter())
            .WithName("ObterRegrasMissao");

        group.MapPut("/", (RegrasMissao novasRegras, RegrasMissaoStore store) =>
        {
            if (novasRegras.MaxLinhasPorMissao < 1)
                return Results.BadRequest(new { erro = "MaxLinhasPorMissao tem de ser pelo menos 1." });

            if (novasRegras.MaxPlataformasPorMissao < 1)
                return Results.BadRequest(new { erro = "MaxPlataformasPorMissao tem de ser pelo menos 1." });

            return Results.Ok(store.Atualizar(novasRegras));
        })
        .WithName("AtualizarRegrasMissao");
    }
}
