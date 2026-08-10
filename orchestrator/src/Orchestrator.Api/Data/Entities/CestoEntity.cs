namespace Orchestrator.Api.Data.Entities;

/// <summary>Tabela orchestrator.CESTOS — tipo de cesto, dimensões e quantos cabem numa palete.</summary>
public class CestoEntity
{
    public string Id { get; set; } = null!;
    public string Codigo { get; set; } = null!;
    public int ComprimentoMm { get; set; }
    public int LarguraMm { get; set; }
    public int AlturaMm { get; set; }
    public int QuantidadePorPalete { get; set; }
}
