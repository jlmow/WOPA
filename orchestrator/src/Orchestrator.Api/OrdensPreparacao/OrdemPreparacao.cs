namespace Orchestrator.Api.OrdensPreparacao;

public record NovaOrdemPreparacaoRequest(string Cliente, DateOnly? DataEntrega, string? MoradaEntrega, IReadOnlyList<string> PsIds);

public record TipificarRequest(decimal? AlturaPaleteCm);

public record PlataformaResumo(string Id, string Codigo, string TipoPlataformaCodigo, int? IndiceCamada, string? ClasseCamada, string Estado, string? CelulaDestino);

public record OrdemPreparacaoResumo(
    string Id,
    string Cliente,
    DateOnly? DataEntrega,
    string? MoradaEntrega,
    string Estado,
    decimal? AlturaPaleteCm,
    DateTime CriadaEm,
    int NPs,
    decimal? VolumeLitros,
    decimal? PesoKg,
    string? TipoIndicativo,
    IReadOnlyList<PlataformaResumo> Plataformas);
