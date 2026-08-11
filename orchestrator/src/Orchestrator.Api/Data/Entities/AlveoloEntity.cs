namespace Orchestrator.Api.Data.Entities;

/// <summary>Tabela orchestrator.ALV — localização física dentro de uma zona.</summary>
public class AlveoloEntity
{
    public string Id { get; set; } = null!;
    public string Codigo { get; set; } = null!;
    public string ZonaId { get; set; } = null!;
    public bool Ativo { get; set; } = true;

    /// <summary>Picking | Reserva | Deposito | Buffer (ADR-030).</summary>
    public string Tipo { get; set; } = "Picking";
    /// <summary>Posição estruturada (ADR-030) — sequenciação de rota dentro do corredor.</summary>
    public string? Corredor { get; set; }
    public int? Coluna { get; set; }
    public int? Nivel { get; set; }

    public ZonaEntity? Zona { get; set; }
}
