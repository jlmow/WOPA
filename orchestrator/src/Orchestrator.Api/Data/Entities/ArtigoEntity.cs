namespace Orchestrator.Api.Data.Entities;

/// <summary>
/// Tabela orchestrator.Artigos — dados mestre de artigo (RF-ENT-03),
/// base da cubicagem (Anexo A.1) e do teste de qualidade de ficha (A.6).
/// </summary>
public class ArtigoEntity
{
    public string Sku { get; set; } = null!;
    public string? Ean { get; set; }
    public string Descricao { get; set; } = null!;
    public int? UnidadesPorCaixa { get; set; }
    public decimal? ComprimentoCaixaCm { get; set; }
    public decimal? LarguraCaixaCm { get; set; }
    public decimal? AlturaCaixaCm { get; set; }
    public decimal? PesoUnitarioKg { get; set; }
    public string? ClasseEmpilhamento { get; set; }
    public int? CaixasPorPaleteCompleta { get; set; }
}
