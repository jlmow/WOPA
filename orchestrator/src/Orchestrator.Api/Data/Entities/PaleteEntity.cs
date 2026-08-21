namespace Orchestrator.Api.Data.Entities;

/// <summary>
/// Tabela orchestrator.Paletes (ADR-035) — equipamento físico reutilizável
/// com matrícula própria. A mesma palete serve tanto para stock parado
/// numa rack (SA/SL.PaleteId) como para a palete de uma missão
/// (Plataformas.PaleteId) — o mesmo Id nas duas situações, sem tabelas
/// separadas. Matrículas pré-carregadas (controller), não inventadas ao
/// ler — o gate de montagem valida contra o que já existe aqui.
/// </summary>
public class PaleteEntity
{
    public string Id { get; set; } = null!;
    public string Matricula { get; set; } = null!;
    public bool Ativa { get; set; } = true;
    /// <summary>ALV onde está parada — NULL enquanto em circulação numa missão.</summary>
    public string? LocalizacaoAtualId { get; set; }
    public DateTime CriadoEm { get; set; } = DateTime.UtcNow;

    public AlveoloEntity? LocalizacaoAtual { get; set; }
}
