using Microsoft.EntityFrameworkCore;
using Orchestrator.Api.Data;

namespace Orchestrator.Api.Modulos;

public static class ModuloEndpoints
{
    public static void MapModuloEndpoints(this WebApplication app)
    {
        app.MapGet("/api/modulos", async (WopaDbContext db) =>
                await db.Modulos
                    .Select(m => new Modulo(m.Slug, m.Nome, m.Disponivel))
                    .ToListAsync())
            .WithTags("Modulos")
            .WithName("ListarModulos");
    }
}
