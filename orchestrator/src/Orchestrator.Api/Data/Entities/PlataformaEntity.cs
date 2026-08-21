namespace Orchestrator.Api.Data.Entities;

/// <summary>
/// Tabela orchestrator.Plataformas — gerada pela tipificação de uma
/// Ordem de Preparação (Anexo A.4/A.5). Cenário A do v0.4 (ordem ≥P1):
/// várias plataformas mono-ordem, cada uma com o seu índice de camada
/// (A.8). Cenário B (plataformas partilhadas P2/P4) ainda não é gerado
/// por este motor — ver ARCHITECTURE.md secção 8.
/// </summary>
public class PlataformaEntity
{
    public string Id { get; set; } = null!;
    public string Codigo { get; set; } = null!;
    public string? OrdemPreparacaoId { get; set; }
    public string TipoPlataformaCodigo { get; set; } = null!;
    public int? IndiceCamada { get; set; }
    public string? ClasseCamada { get; set; }
    public string? CelulaDestino { get; set; }
    public string Estado { get; set; } = "EmPicking";
    public DateTime CriadaEm { get; set; } = DateTime.UtcNow;

    /// <summary>Gate de montagem (ADR-029) — preenchidos na primeira zona que monta a plataforma.</summary>
    [Obsolete("Substituído por PaleteId (ADR-035) — texto solto sem validação, já não é escrito. Fica sem uso, coluna não apagada (ADR-017).")]
    public string? MatriculaPalete { get; set; }
    public DateTime? MontadaEm { get; set; }

    /// <summary>A palete (equipamento reutilizável, ADR-035) montada nesta plataforma — FK a Paletes, não texto solto.</summary>
    public string? PaleteId { get; set; }

    public TipoPlataformaEntity? TipoPlataforma { get; set; }
}
