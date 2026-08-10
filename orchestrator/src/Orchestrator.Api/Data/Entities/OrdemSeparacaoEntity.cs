namespace Orchestrator.Api.Data.Entities;

/// <summary>
/// Tabela orchestrator.OrdensSeparacao — "PS" (pedido de separação) do
/// documento de requisitos v0.4 (ADR-011/ADR-015). Ganhou os campos de
/// RF-ENT-01 (canal/cliente/morada/data) e a ligação a
/// OrdensPreparacao quando o supervisor a agrupa.
/// </summary>
public class OrdemSeparacaoEntity
{
    public string Id { get; set; } = null!;
    public string NumeroDocumento { get; set; } = null!;
    public string Origem { get; set; } = null!;
    public DateTime RecebidaEm { get; set; } = DateTime.UtcNow;
    public bool Processada { get; set; }
    public string? MissaoId { get; set; }
    public string? Cliente { get; set; }
    public DateOnly? DataEntrega { get; set; }
    public string? MoradaEntrega { get; set; }
    /// <summary>ONLINE | B2B | FISICAS | CNUS (secção 2.1).</summary>
    public string? Canal { get; set; }
    public string? OrdemPreparacaoId { get; set; }

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
