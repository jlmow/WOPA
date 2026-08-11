namespace Orchestrator.Api.Data.Entities;

/// <summary>
/// Tabela orchestrator.OrdensPreparacao — "ordem de preparação" do
/// documento de requisitos v0.4. Chega já composta de outro software
/// (agrupamento de PS por cliente/data/morada já feito lá) — o WOPA só
/// recebe e guarda via POST /api/ordens-preparacao (ADR-017). É a
/// partir daqui que o WOPA trata das etapas seguintes: cubicar,
/// tipificar (gerar Plataformas) e despachar.
/// </summary>
public class OrdemPreparacaoEntity
{
    public string Id { get; set; } = null!;
    public string Cliente { get; set; } = null!;
    public DateOnly? DataEntrega { get; set; }
    public string? MoradaEntrega { get; set; }
    public string Estado { get; set; } = "Aberta";
    public decimal? AlturaPaleteCm { get; set; }
    public DateTime RecebidaEm { get; set; } = DateTime.UtcNow;

    /// <summary>Marcada pelo supervisor no controller (ADR-027) — não vem da origem.</summary>
    public bool Urgente { get; set; }
    public DateTime? DataLimite { get; set; }

    public List<OrdemSeparacaoEntity> Ps { get; set; } = new();
    public List<PlataformaEntity> Plataformas { get; set; } = new();
}
