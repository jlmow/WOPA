using Microsoft.EntityFrameworkCore;
using Orchestrator.Api.Data;

namespace Orchestrator.Api.Zonas;

public static class ZonaEndpoints
{
    public static void MapZonaEndpoints(this WebApplication app)
    {
        app.MapGet("/api/zonas", async (WopaDbContext db) =>
                await db.Zonas
                    .Select(z => new Zona(z.Id, z.Codigo, z.Nome))
                    .ToListAsync())
            .WithTags("Zonas")
            .WithName("ListarZonas");
    }
}
