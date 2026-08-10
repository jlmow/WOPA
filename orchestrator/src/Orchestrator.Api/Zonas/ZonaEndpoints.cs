namespace Orchestrator.Api.Zonas;

public static class ZonaEndpoints
{
    // PoC: lista fixa. Numa fase seguinte vem do schema de configuração do
    // armazém na base de dados WOPA (definida a partir do controller).
    private static readonly Zona[] Zonas =
    [
        new("zona-a", "A", "Picking geral"),
        new("zona-b", "B", "Volumosos"),
        new("zona-c", "C", "Frio"),
        new("doca-1", "Doca 1", "Expedição")
    ];

    public static void MapZonaEndpoints(this WebApplication app)
    {
        app.MapGet("/api/zonas", () => Zonas).WithTags("Zonas").WithName("ListarZonas");
    }
}
