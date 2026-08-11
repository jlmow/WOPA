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

    /// <summary>
    /// Campos da query real de tipificação do PHC (ADR-032). Quando
    /// TipoPlataformaCodigo/NPlataformas vêm preenchidos, o "Tipificar"
    /// materializa-os diretamente em vez de recalcular por cubicagem —
    /// a Ordem já chega tipificada de lá. Os restantes são só para
    /// rastreabilidade contra a origem.
    /// </summary>
    public string? ReferenciaExterna { get; set; }
    public int? NumeroOrdem { get; set; }
    public int? NumeroPedido { get; set; }
    public int? NumeroProforma { get; set; }
    public string? TipoPlataformaCodigo { get; set; }
    public int? NPlataformas { get; set; }
    public int? NumRefs { get; set; }
    public int? TotalCaixas { get; set; }
    public decimal? VolumeTotalCm3 { get; set; }
    public decimal? PesoTotalKg { get; set; }
    public int? RefsSemFicha { get; set; }
    public string? Observacoes { get; set; }

    public List<OrdemSeparacaoEntity> Ps { get; set; } = new();
    public List<PlataformaEntity> Plataformas { get; set; } = new();
}
