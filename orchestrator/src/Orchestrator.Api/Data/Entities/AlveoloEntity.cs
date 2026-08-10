namespace Orchestrator.Api.Data.Entities;

/// <summary>Tabela orchestrator.ALV — localização física dentro de uma zona.</summary>
public class AlveoloEntity
{
    public string Id { get; set; } = null!;
    public string Codigo { get; set; } = null!;
    public string ZonaId { get; set; } = null!;
    public bool Ativo { get; set; } = true;

    public ZonaEntity? Zona { get; set; }
}
