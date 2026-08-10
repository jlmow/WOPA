namespace Orchestrator.Api.Data.Entities;

/// <summary>Tabela orchestrator.TiposPlataforma — P0/P1/P2/P4, dimensões e altura.</summary>
public class TipoPlataformaEntity
{
    public string Codigo { get; set; } = null!;
    public string Descricao { get; set; } = null!;
    public int ComprimentoMm { get; set; }
    public int LarguraMm { get; set; }
    public int AlturaMm { get; set; }
    public int CestosPorPlataforma { get; set; }
}
