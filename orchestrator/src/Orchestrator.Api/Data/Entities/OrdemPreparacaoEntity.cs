namespace Orchestrator.Api.Data.Entities;

/// <summary>
/// Tabela orchestrator.OrdensPreparacao — "ordem de preparação" do
/// documento de requisitos v0.4: agrupa PS (OrdensSeparacao) por
/// cliente/data/morada de entrega; é a unidade que se cubica, tipifica
/// (gera Plataformas) e despacha.
/// </summary>
public class OrdemPreparacaoEntity
{
    public string Id { get; set; } = null!;
    public string Cliente { get; set; } = null!;
    public DateOnly? DataEntrega { get; set; }
    public string? MoradaEntrega { get; set; }
    public string Estado { get; set; } = "Aberta";
    public decimal? AlturaPaleteCm { get; set; }
    public DateTime CriadaEm { get; set; } = DateTime.UtcNow;

    public List<OrdemSeparacaoEntity> Ps { get; set; } = new();
    public List<PlataformaEntity> Plataformas { get; set; } = new();
}
