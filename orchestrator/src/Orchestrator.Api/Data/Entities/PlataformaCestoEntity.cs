namespace Orchestrator.Api.Data.Entities;

/// <summary>
/// Tabela orchestrator.PlataformaCestos (ADR-029) — matrículas dos cestos
/// físicos montados numa plataforma P1/P2/P4, lidas pelo operador no
/// gate de montagem (ver PickingEndpoints).
/// </summary>
public class PlataformaCestoEntity
{
    public string Id { get; set; } = null!;
    public string PlataformaId { get; set; } = null!;
    public string MatriculaCesto { get; set; } = null!;
    public DateTime CriadoEm { get; set; } = DateTime.UtcNow;
}
