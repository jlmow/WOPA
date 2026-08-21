namespace Orchestrator.Api.Data.Entities;

/// <summary>
/// Tabela orchestrator.CestoInstancias (ADR-030) — cesto físico com
/// matrícula própria, equipamento reutilizável (distinto de CESTOS, que
/// continua a ser só o tipo/spec). Estado Livre = no depósito, à espera
/// de ser montado; EmUso = montado numa plataforma em circulação.
/// </summary>
public class CestoInstanciaEntity
{
    public string Id { get; set; } = null!;
    public string Matricula { get; set; } = null!;
    public string TipoCestoId { get; set; } = null!;
    public string Estado { get; set; } = "Livre";
    /// <summary>ALV onde está parado — NULL enquanto EmUso (em circulação, sem alvéolo fixo).</summary>
    public string? LocalizacaoAtualId { get; set; }
    public DateTime CriadoEm { get; set; } = DateTime.UtcNow;

    public CestoEntity? TipoCesto { get; set; }
    public AlveoloEntity? LocalizacaoAtual { get; set; }
}
