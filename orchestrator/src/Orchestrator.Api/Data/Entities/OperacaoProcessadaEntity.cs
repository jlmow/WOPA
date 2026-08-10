namespace Orchestrator.Api.Data.Entities;

/// <summary>
/// Tabela picking.OperacoesProcessadas — idempotência (ADR-007). Não
/// guarda um snapshot do resultado: ao repetir um operacaoId já
/// processado, devolve-se o estado ATUAL da linha (ver PickingEndpoints)
/// em vez de reaplicar o efeito.
/// </summary>
public class OperacaoProcessadaEntity
{
    public string OperacaoId { get; set; } = null!;
    public string MissaoLinhaId { get; set; } = null!;
    public string Tipo { get; set; } = null!;
    public DateTime ProcessadoEm { get; set; } = DateTime.UtcNow;
}
