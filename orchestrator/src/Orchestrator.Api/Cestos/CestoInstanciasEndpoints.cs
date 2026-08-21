using Microsoft.EntityFrameworkCore;
using Orchestrator.Api.Data;
using Orchestrator.Api.Data.Entities;

namespace Orchestrator.Api.Cestos;

public record CestoInstanciaDto(string Id, string Matricula, string TipoCestoCodigo, string Estado, string? LocalizacaoCodigo);

public record NovoCestoInstanciaRequest(string Matricula);

/// <summary>
/// Registo de cestos físicos (ADR-030/035) — matrícula própria,
/// pré-carregada aqui (ecrã do controller), não inventada ao ler no
/// gate de montagem do pda. Só há um tipo de cesto seedado por agora
/// ("cesto-standard") — usado por omissão; revisitar quando houver mais
/// do que um tipo real.
/// </summary>
public static class CestoInstanciasEndpoints
{
    public static void MapCestoInstanciasEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/cestos-instancias").WithTags("CestoInstancias");

        group.MapGet("/", async (WopaDbContext db) =>
        {
            var cestos = await db.CestoInstancias
                .Include(c => c.TipoCesto)
                .Include(c => c.LocalizacaoAtual)
                .OrderBy(c => c.Matricula)
                .ToListAsync();
            return cestos.Select(ParaDto);
        })
        .WithName("ListarCestoInstancias");

        group.MapPost("/", async (NovoCestoInstanciaRequest pedido, WopaDbContext db) =>
        {
            if (string.IsNullOrWhiteSpace(pedido.Matricula))
                return Results.BadRequest(new { erro = "matricula é obrigatória." });

            if (await db.CestoInstancias.AnyAsync(c => c.Matricula == pedido.Matricula))
                return Results.Conflict(new { erro = "Já existe um cesto com esta matrícula." });

            var tipoCestoId = await db.Cestos.Select(c => c.Id).FirstOrDefaultAsync();
            if (tipoCestoId is null)
                return Results.Conflict(new { erro = "Não existe nenhum tipo de cesto configurado (tabela CESTOS)." });

            var cesto = new CestoInstanciaEntity
            {
                Id = Guid.NewGuid().ToString("n"),
                Matricula = pedido.Matricula,
                TipoCestoId = tipoCestoId,
            };
            db.CestoInstancias.Add(cesto);
            await db.SaveChangesAsync();

            cesto = await db.CestoInstancias.Include(c => c.TipoCesto).SingleAsync(c => c.Id == cesto.Id);
            return Results.Created($"/api/cestos-instancias/{cesto.Id}", ParaDto(cesto));
        })
        .WithName("CriarCestoInstancia");
    }

    private static CestoInstanciaDto ParaDto(CestoInstanciaEntity c) =>
        new(c.Id, c.Matricula, c.TipoCesto?.Codigo ?? c.TipoCestoId, c.Estado, c.LocalizacaoAtual?.Codigo);
}
