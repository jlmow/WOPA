namespace Orchestrator.Api.Data.Entities;

/// <summary>
/// Tabela orchestrator.OrdensSeparacao — "PS" (pedido de separação) do
/// documento de requisitos v0.4. Chega sempre dentro de uma Ordem de
/// Preparação já composta por outro software (ADR-017) — não existe
/// como registo solto à espera de agrupamento no WOPA.
/// </summary>
public class OrdemSeparacaoEntity
{
    public string Id { get; set; } = null!;
    public string OrdemPreparacaoId { get; set; } = null!;
    public string NumeroDocumento { get; set; } = null!;
    public string Origem { get; set; } = null!;
    /// <summary>ONLINE | B2B | FISICAS | CNUS (secção 2.1).</summary>
    public string? Canal { get; set; }
    public DateTime RecebidaEm { get; set; } = DateTime.UtcNow;

    public List<OrdemSeparacaoLinhaEntity> Linhas { get; set; } = new();
}

/// <summary>Tabela orchestrator.OrdensSeparacaoLinhas.</summary>
public class OrdemSeparacaoLinhaEntity
{
    public string Id { get; set; } = null!;
    public string OrdemSeparacaoId { get; set; } = null!;
    public string Sku { get; set; } = null!;
    public int Quantidade { get; set; }
    public string? AlveoloId { get; set; }
    /// <summary>
    /// A que plataforma esta linha foi destinada pela tipificação
    /// (A.5). Distribuição round-robin quando a ordem gera várias
    /// plataformas — simplificação da PoC, ver ARCHITECTURE.md secção 8.
    /// </summary>
    public string? PlataformaId { get; set; }

    public AlveoloEntity? Alveolo { get; set; }
}
