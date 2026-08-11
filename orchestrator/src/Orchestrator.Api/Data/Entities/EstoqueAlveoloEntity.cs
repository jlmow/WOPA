namespace Orchestrator.Api.Data.Entities;

/// <summary>
/// Tabela SA — stock atual por artigo e alvéolo (a "fotografia" que o
/// SL/<see cref="MovimentoStockEntity"/> vai atualizando). Chave composta
/// (Sku, AlveoloId), ver WopaDbContext.
/// </summary>
public class EstoqueAlveoloEntity
{
    public string Sku { get; set; } = null!;
    public string AlveoloId { get; set; } = null!;
    public int Quantidade { get; set; }
    public DateTime AtualizadoEm { get; set; }

    public AlveoloEntity? Alveolo { get; set; }
}
