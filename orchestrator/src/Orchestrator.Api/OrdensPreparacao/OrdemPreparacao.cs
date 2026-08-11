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
///
/// TipoPlataformaCodigo/NPlataformas (ADR-032): quando a origem já
/// decidiu a tipificação (query real do PHC), o "Tipificar" materializa
/// estes valores diretamente em vez de recalcular por cubicagem. Os
/// restantes campos novos são só para rastreabilidade contra a origem.
/// </summary>
public record NovaOrdemPreparacaoRequest(
    string Cliente,
    DateOnly? DataEntrega,
    string? MoradaEntrega,
    IReadOnlyList<PsRecebido> Ps,
    string? ReferenciaExterna = null,
    int? NumeroOrdem = null,
    int? NumeroPedido = null,
    int? NumeroProforma = null,
    string? TipoPlataformaCodigo = null,
    int? NPlataformas = null,
    int? NumRefs = null,
    int? TotalCaixas = null,
    decimal? VolumeTotalCm3 = null,
    decimal? PesoTotalKg = null,
    int? RefsSemFicha = null,
    string? Observacoes = null);

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
    DateTime? DataLimite,
    string? ReferenciaExterna,
    int? NumeroOrdem,
    int? NumeroPedido,
    string? TipoPlataformaOrigem,
    int? NPlataformasOrigem,
    int? RefsSemFicha,
    string? Observacoes);

/// <summary>ADR-027: marcada pelo supervisor no controller, não vem da origem.</summary>
public record UrgenteRequest(bool Urgente, DateTime? DataLimite);
