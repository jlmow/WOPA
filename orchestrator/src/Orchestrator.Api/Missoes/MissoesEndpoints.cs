using Microsoft.EntityFrameworkCore;
using Orchestrator.Api.Data;
using Orchestrator.Api.Picking;

namespace Orchestrator.Api.Missoes;

/// <summary>
/// Gestão de missões para o `controller` (RF-CTL-09/10): fila de
/// trabalho, com motivo/antiguidade, e as três ações do supervisor
/// sobre uma missão incompleta (A.13) — fechar, retomar, reatribuir.
/// </summary>
public static class MissoesEndpoints
{
    public static void MapMissoesEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/missoes").WithTags("Missoes");

        group.MapGet("/", async (WopaDbContext db) =>
        {
            var missoes = await db.Missoes
                .Include(m => m.Linhas)
                .OrderByDescending(m => m.CriadaEm)
                .ToListAsync();

            var plataformaIds = missoes.Where(m => m.PlataformaId is not null).Select(m => m.PlataformaId!).Distinct().ToList();
            var codigosPorPlataforma = await db.Plataformas
                .Where(p => plataformaIds.Contains(p.Id))
                .ToDictionaryAsync(p => p.Id, p => p.Codigo);

            return missoes.Select(m => ParaDto(m, codigosPorPlataforma));
        })
        .WithName("ListarMissoes");

        // A.13: pausada -> aberta e incompleta, com motivo tipificado.
        group.MapPost("/{id}/pausar", async (string id, PausarRequest pedido, WopaDbContext db) =>
        {
            var missao = await db.Missoes.Include(m => m.Linhas).SingleOrDefaultAsync(m => m.Id == id);
            if (missao is null) return Results.NotFound();
            if (missao.Estado != "EmExecucao")
                return Results.Conflict(new { erro = $"Só se pode pausar uma missão em execução (estado atual: {missao.Estado})." });

            missao.Estado = "Pausada";
            missao.MotivoPausa = pedido.Motivo;
            missao.PausadaEm = DateTime.UtcNow;
            await db.SaveChangesAsync();

            var codigos = await CodigosPorPlataformaAsync(db, missao);
            return Results.Ok(ParaDto(missao, codigos));
        })
        .WithName("PausarMissao");

        // A.13: retomar — o mesmo operador (ou outro, via reatribuir) completa o que falta.
        group.MapPost("/{id}/retomar", async (string id, WopaDbContext db) =>
        {
            var missao = await db.Missoes.Include(m => m.Linhas).SingleOrDefaultAsync(m => m.Id == id);
            if (missao is null) return Results.NotFound();
            if (missao.Estado != "Pausada")
                return Results.Conflict(new { erro = $"Só se pode retomar uma missão pausada (estado atual: {missao.Estado})." });

            missao.Estado = "EmExecucao";
            missao.MotivoPausa = null;
            missao.RetomadaEm = DateTime.UtcNow;
            await db.SaveChangesAsync();

            var codigos = await CodigosPorPlataformaAsync(db, missao);
            return Results.Ok(ParaDto(missao, codigos));
        })
        .WithName("RetomarMissao");

        // A.13: fechar — o remanescente não se executa.
        group.MapPost("/{id}/fechar", async (string id, WopaDbContext db) =>
        {
            var missao = await db.Missoes.Include(m => m.Linhas).SingleOrDefaultAsync(m => m.Id == id);
            if (missao is null) return Results.NotFound();
            if (missao.Estado is "Concluida" or "FechadaIncompleta")
                return Results.Conflict(new { erro = $"Esta missão já não está ativa (estado atual: {missao.Estado})." });

            missao.Estado = "FechadaIncompleta";
            missao.ConcluidaEm = DateTime.UtcNow;
            await db.SaveChangesAsync();

            var codigos = await CodigosPorPlataformaAsync(db, missao);
            return Results.Ok(ParaDto(missao, codigos));
        })
        .WithName("FecharMissao");

        // A.13: reatribuir — muda o operador/terminal responsável e volta a pôr a missão disponível.
        group.MapPost("/{id}/reatribuir", async (string id, ReatribuirRequest pedido, WopaDbContext db) =>
        {
            var missao = await db.Missoes.Include(m => m.Linhas).SingleOrDefaultAsync(m => m.Id == id);
            if (missao is null) return Results.NotFound();
            if (missao.Estado == "Concluida")
                return Results.Conflict(new { erro = "Não é possível reatribuir uma missão já concluída." });

            missao.UtilizadorId = pedido.UtilizadorId;
            missao.TerminalId = pedido.TerminalId;
            missao.Estado = "Atribuida";
            missao.MotivoPausa = null;
            missao.AtribuidaEm = DateTime.UtcNow;
            await db.SaveChangesAsync();

            var codigos = await CodigosPorPlataformaAsync(db, missao);
            return Results.Ok(ParaDto(missao, codigos));
        })
        .WithName("ReatribuirMissao");
    }

    private static async Task<IReadOnlyDictionary<string, string>> CodigosPorPlataformaAsync(WopaDbContext db, Data.Entities.MissaoEntity missao)
    {
        if (missao.PlataformaId is null) return new Dictionary<string, string>();
        var codigo = await db.Plataformas.Where(p => p.Id == missao.PlataformaId).Select(p => p.Codigo).SingleOrDefaultAsync();
        return codigo is null ? new Dictionary<string, string>() : new Dictionary<string, string> { [missao.PlataformaId] = codigo };
    }

    private static MissaoResumo ParaDto(Data.Entities.MissaoEntity m, IReadOnlyDictionary<string, string> codigosPorPlataforma) => new(
        m.Id,
        m.Codigo,
        m.CentroTrabalho,
        m.ZonaId,
        m.PlataformaId is { } pid && codigosPorPlataforma.TryGetValue(pid, out var cod) ? cod : null,
        m.PlataformaConfirmada,
        m.UtilizadorId,
        m.Estado,
        m.MotivoPausa,
        m.CriadaEm,
        m.AtribuidaEm,
        m.IniciadaEm,
        m.PausadaEm,
        m.ConcluidaEm,
        m.Linhas.Count,
        m.Linhas.Count(l => l.Estado == PickingTaskStatus.Concluida));
}
