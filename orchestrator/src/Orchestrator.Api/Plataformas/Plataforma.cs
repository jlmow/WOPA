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

public record DespacharRequest(string? CelulaDestino);
