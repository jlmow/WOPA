using Microsoft.EntityFrameworkCore;
using Orchestrator.Api.Data;

namespace Orchestrator.Api.Config;

public static class RegrasMissaoEndpoints
{
    private const string ChaveDefault = "default";

    public static void MapRegrasMissaoEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/config/regras-missao").WithTags("Config");

        group.MapGet("/", async (WopaDbContext db) =>
                await db.RegrasMissao.SingleAsync(r => r.Chave == ChaveDefault))
            .WithName("ObterRegrasMissao");

        group.MapPut("/", async (RegrasMissao novasRegras, WopaDbContext db) =>
        {
            if (novasRegras.MaxLinhasPorMissao < 1)
                return Results.BadRequest(new { erro = "MaxLinhasPorMissao tem de ser pelo menos 1." });

            if (novasRegras.MaxPlataformasPorMissao < 1)
                return Results.BadRequest(new { erro = "MaxPlataformasPorMissao tem de ser pelo menos 1." });

            var atuais = await db.RegrasMissao.SingleAsync(r => r.Chave == ChaveDefault);
            atuais.MaxLinhasPorMissao = novasRegras.MaxLinhasPorMissao;
            atuais.MaxPlataformasPorMissao = novasRegras.MaxPlataformasPorMissao;
            atuais.CriterioAgrupamento = novasRegras.CriterioAgrupamento;
            atuais.CriterioOrdenacao = novasRegras.CriterioOrdenacao;
            atuais.AtualizadoEm = DateTime.UtcNow;

            await db.SaveChangesAsync();
            return Results.Ok(atuais);
        })
        .WithName("AtualizarRegrasMissao");
    }
}
