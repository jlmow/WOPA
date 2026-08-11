namespace Orchestrator.Api.Data.Entities;

/// <summary>
/// Tabela SL — ledger de movimentos de stock. Cada pick confirmado no
/// pda (RF-PIC) gera aqui uma linha (CodigoMovimentoId = 501, "Saída por
/// picking") e decrementa o <see cref="EstoqueAlveoloEntity"/> correspondente.
/// </summary>
public class MovimentoStockEntity
{
    public long Id { get; set; }
    public int CodigoMovimentoId { get; set; }
    public string Sku { get; set; } = null!;
    public string AlveoloId { get; set; } = null!;
    public int Quantidade { get; set; }
    public string? MissaoLinhaId { get; set; }
    public DateTime CriadoEm { get; set; }

    /// <summary>Motivo da exceção (ADR-027) — só preenchido quando a quantidade picada difere da sugerida (ex.: "Falta de stock").</summary>
    public string? Motivo { get; set; }
}
