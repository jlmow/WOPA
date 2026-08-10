namespace Orchestrator.Api.OrdensSeparacao;

/// <summary>
/// Uma linha da ordem — um artigo e a quantidade a separar. AlveoloCodigo
/// é opcional porque nem toda origem (PHC/OrdersHub) tem necessariamente
/// essa informação disponível — o controller decide o alvéolo real ao
/// montar a missão, se não vier preenchido.
/// </summary>
public record OrdemSeparacaoLinha(string Sku, int Quantidade, string? AlveoloCodigo);

/// <summary>
/// Recebida via POST /api/ordens-separacao, independentemente de vir do
/// PHC ou do OrdersHub (ADR-008/011) — é o ponto onde o trabalho do
/// controller começa: criar missões a partir destas ordens.
/// </summary>
public class OrdemSeparacao
{
    public required string Id { get; init; }
    public required string NumeroDocumento { get; init; }
    public required string Origem { get; init; }
    public DateTime RecebidaEm { get; init; } = DateTime.UtcNow;
    public bool Processada { get; set; }
    public required IReadOnlyList<OrdemSeparacaoLinha> Linhas { get; init; }
}

public record NovaOrdemSeparacaoRequest(string NumeroDocumento, string Origem, IReadOnlyList<OrdemSeparacaoLinha> Linhas);
