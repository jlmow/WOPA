namespace Orchestrator.Api.Data.Entities;

/// <summary>Tabela picking.MISSAO — nome exato pedido pelo cliente.</summary>
public class MissaoEntity
{
    public string Id { get; set; } = null!;
    public string Codigo { get; set; } = null!;
    public string? ZonaId { get; set; }
    public string? UtilizadorId { get; set; }
    public string? TerminalId { get; set; }
    public string Estado { get; set; } = "Pendente";
    public DateTime CriadaEm { get; set; } = DateTime.UtcNow;
    public DateTime? ConcluidaEm { get; set; }

    public List<MissaoLinhaEntity> Linhas { get; set; } = new();
}
