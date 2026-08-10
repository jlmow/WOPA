namespace Orchestrator.Api.Modulos;

public static class ModuloEndpoints
{
    // PoC: lista fixa dos módulos PDA. Numa fase seguinte reflete as
    // permissões reais do operador, definidas no controller.
    private static readonly Modulo[] Modulos =
    [
        new("picking", "Picking", true),
        new("transporte", "Transporte", false),
        new("abastecimento", "Abastecimento", false)
    ];

    public static void MapModuloEndpoints(this WebApplication app)
    {
        app.MapGet("/api/modulos", () => Modulos).WithTags("Modulos").WithName("ListarModulos");
    }
}
