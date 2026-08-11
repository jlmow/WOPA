using Orchestrator.Api.OrdensSeparacao;

namespace Orchestrator.Api.OrdensPreparacao;

/// <summary>
/// Um PS (pedido de separação) tal como chega dentro de uma Ordem de
/// Preparação já composta por outro software (ADR-017) — reaproveita o
/// mesmo formato de linha de <see cref="OrdensSeparacao.OrdemSeparacao"/>.
/// </summary>
public record PsRecebido(string NumeroDocumento, string Origem, string? Canal, IReadOnlyList<OrdemSeparacaoLinha> Linhas);

/// <summary>
/// Corpo de POST /api/ordens-preparacao: a Ordem de Preparação chega já
/// composta (cliente/data/morada e os PS que a compõem já decididos
/// noutro software) — o WOPA só a recebe e guarda (ADR-017).
/// </summary>
public record NovaOrdemPreparacaoRequest(string Cliente, DateOnly? DataEntrega, string? MoradaEntrega, IReadOnlyList<PsRecebido> Ps);

public record TipificarRequest(decimal? AlturaPaleteCm);

public record PlataformaResumo(string Id, string Codigo, string TipoPlataformaCodigo, int? IndiceCamada, string? ClasseCamada, string Estado, string? CelulaDestino);

public record OrdemPreparacaoResumo(
    string Id,
    string Cliente,
    DateOnly? DataEntrega,
    string? MoradaEntrega,
    string Estado,
    decimal? AlturaPaleteCm,
    DateTime RecebidaEm,
    int NPs,
    decimal? VolumeLitros,
    decimal? PesoKg,
    string? TipoIndicativo,
    IReadOnlyList<PlataformaResumo> Plataformas,
    bool Urgente,
    DateTime? DataLimite);

/// <summary>ADR-027: marcada pelo supervisor no controller, não vem da origem.</summary>
public record UrgenteRequest(bool Urgente, DateTime? DataLimite);
