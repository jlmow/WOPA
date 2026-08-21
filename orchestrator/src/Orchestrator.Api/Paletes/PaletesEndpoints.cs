using Microsoft.EntityFrameworkCore;
using Orchestrator.Api.Data;
using Orchestrator.Api.Data.Entities;

namespace Orchestrator.Api.Paletes;

public record PaleteDto(string Id, string Matricula, bool Ativa, string? LocalizacaoCodigo);

public record NovaPaleteRequest(string Matricula);

/// <summary>
/// Registo de paletes (ADR-035) — equipamento físico reutilizável, com
/// matrícula própria. Pré-carregadas aqui (ecrã do controller), não
/// inventadas ao ler no gate de montagem/pick do pda — sem matrícula
/// registada aqui, o pda recusa.
/// </summary>
public static class PaletesEndpoints
{
    public static void MapPaletesEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/paletes").WithTags("Paletes");

        group.MapGet("/", async (WopaDbContext db) =>
        {
            var paletes = await db.Paletes.Include(p => p.LocalizacaoAtual).OrderBy(p => p.Matricula).ToListAsync();
            return paletes.Select(ParaDto);
        })
        .WithName("ListarPaletes");

        group.MapPost("/", async (NovaPaleteRequest pedido, WopaDbContext db) =>
        {
            if (string.IsNullOrWhiteSpace(pedido.Matricula))
                return Results.BadRequest(new { erro = "matricula é obrigatória." });

            if (await db.Paletes.AnyAsync(p => p.Matricula == pedido.Matricula))
                return Results.Conflict(new { erro = "Já existe uma palete com esta matrícula." });

            var palete = new PaleteEntity { Id = Guid.NewGuid().ToString("n"), Matricula = pedido.Matricula };
            db.Paletes.Add(palete);
            await db.SaveChangesAsync();

            return Results.Created($"/api/paletes/{palete.Id}", ParaDto(palete));
        })
        .WithName("CriarPalete");
    }

    private static PaleteDto ParaDto(PaleteEntity p) => new(p.Id, p.Matricula, p.Ativa, p.LocalizacaoAtual?.Codigo);
}
