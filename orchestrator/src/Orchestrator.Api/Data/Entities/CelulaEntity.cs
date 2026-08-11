namespace Orchestrator.Api.Data.Entities;

/// <summary>
/// Tabela Celulas — recurso de capacidade (packing/montagem/consolidação),
/// ADR-027. Capacidade diária simples (constante), não um calendário completo.
/// </summary>
public class CelulaEntity
{
    public string Id { get; set; } = null!;
    public string Codigo { get; set; } = null!;
    public string Nome { get; set; } = null!;
    public int CapacidadeDiariaUnidades { get; set; }
    public bool Ativa { get; set; } = true;
}
