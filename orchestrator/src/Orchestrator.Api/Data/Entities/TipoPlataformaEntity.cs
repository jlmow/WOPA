namespace Orchestrator.Api.Data.Entities;

/// <summary>
/// Tabela orchestrator.TiposPlataforma — P1/P2/P4, dimensões e
/// capacidade útil (margem de 20% já aplicada). P0 não é um tipo de
/// plataforma (é o fluxo direto de paletes completas) — ver
/// ARCHITECTURE.md secção 4.7 / ADR-015.
/// </summary>
public class TipoPlataformaEntity
{
    public string Codigo { get; set; } = null!;
    public string Descricao { get; set; } = null!;
    public int ComprimentoMm { get; set; }
    public int LarguraMm { get; set; }
    public int AlturaMm { get; set; }
    public int CestosPorPlataforma { get; set; }
    public int CapacidadeUtilLitros { get; set; }
}
