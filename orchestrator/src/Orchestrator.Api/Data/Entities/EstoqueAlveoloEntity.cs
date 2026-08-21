namespace Orchestrator.Api.Data.Entities;

/// <summary>
/// Tabela SA — stock atual por artigo, alvéolo E palete de origem (a
/// "fotografia" que o SL/<see cref="MovimentoStockEntity"/> vai
/// atualizando). Chave composta (Sku, AlveoloId, PaleteId) — ADR-035:
/// uma palete pode ter mais do que 1 SKU, um alvéolo pode ter mais do
/// que 1 palete, ver WopaDbContext.
/// </summary>
public class EstoqueAlveoloEntity
{
    public string Sku { get; set; } = null!;
    public string AlveoloId { get; set; } = null!;
    public string PaleteId { get; set; } = null!;
    public int Quantidade { get; set; }
    public DateTime AtualizadoEm { get; set; }

    public AlveoloEntity? Alveolo { get; set; }
    public PaleteEntity? Palete { get; set; }
}
