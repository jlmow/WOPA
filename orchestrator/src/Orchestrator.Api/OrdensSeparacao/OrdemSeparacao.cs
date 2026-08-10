namespace Orchestrator.Api.OrdensSeparacao;

/// <summary>
/// Uma linha da ordem — um artigo e a quantidade a separar. AlveoloCodigo
/// é opcional porque nem toda origem (PHC/OrdersHub) tem necessariamente
/// essa informação disponível — o controller decide o alvéolo real ao
/// montar a missão, se não vier preenchido.
/// </summary>
public record OrdemSeparacaoLinha(string Sku, int Quantidade, string? AlveoloCodigo);

/// <summary>
/// "PS" (pedido de separação) do documento de requisitos v0.4. Recebida
/// via POST /api/ordens-separacao, independentemente de vir do PHC ou
/// do OrdersHub (ADR-008/011) — é o ponto onde o trabalho do
/// `controller` começa: agrupar PS em Ordens de Preparação (RF-CTL-02).
/// </summary>
public class OrdemSeparacao
{
    public required string Id { get; init; }
    public required string NumeroDocumento { get; init; }
    public required string Origem { get; init; }
    public DateTime RecebidaEm { get; init; } = DateTime.UtcNow;
    public bool Processada { get; set; }
    public string? Cliente { get; init; }
    public DateOnly? DataEntrega { get; init; }
    public string? MoradaEntrega { get; init; }
    public string? Canal { get; init; }
    public string? OrdemPreparacaoId { get; init; }
    public required IReadOnlyList<OrdemSeparacaoLinha> Linhas { get; init; }

    /// <summary>Cubicagem/tipificação indicativa (RF-CTL-01) — nulo se ainda não foi calculada.</summary>
    public CubicagemIndicativa? Cubicagem { get; set; }
}

public record CubicagemIndicativa(decimal VolumeLitros, decimal PesoKg, int NRefs, int NLinhasNaoCubicaveis, string? TipoIndicativo);

public record NovaOrdemSeparacaoRequest(
    string NumeroDocumento,
    string Origem,
    IReadOnlyList<OrdemSeparacaoLinha> Linhas,
    string? Cliente = null,
    DateOnly? DataEntrega = null,
    string? MoradaEntrega = null,
    string? Canal = null);
