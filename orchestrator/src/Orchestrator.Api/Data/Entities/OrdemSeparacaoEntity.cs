namespace Orchestrator.Api.Data.Entities;

/// <summary>Tabela orchestrator.OrdensSeparacao (ADR-011).</summary>
public class OrdemSeparacaoEntity
{
    public string Id { get; set; } = null!;
    public string NumeroDocumento { get; set; } = null!;
    public string Origem { get; set; } = null!;
    public DateTime RecebidaEm { get; set; } = DateTime.UtcNow;
    public bool Processada { get; set; }
    public string? MissaoId { get; set; }

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

    public AlveoloEntity? Alveolo { get; set; }
}
