namespace Orchestrator.Api.Plataformas;

public record PlataformaDto(
    string Id,
    string Codigo,
    string? OrdemPreparacaoId,
    string? Cliente,
    string TipoPlataformaCodigo,
    int? IndiceCamada,
    string? ClasseCamada,
    string? CelulaDestino,
    string Estado,
    string? MissaoId);

// DataDespacho (ADR-027): dia para o qual o trabalho fica agendado. Vazio
// ou hoje/passado -> comportamento antigo (Missão "Criada", disponível já).
// Futuro -> Missão nasce "Planeada", só entra no circuito do pda quando o
// dia chegar (ver PickingEndpoints.ObterOuAtribuirMissaoAtualAsync).
public record DespacharRequest(string? CelulaDestino, string? CelulaId, DateOnly? DataDespacho);
