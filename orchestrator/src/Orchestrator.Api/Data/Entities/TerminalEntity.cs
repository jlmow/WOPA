namespace Orchestrator.Api.Data.Entities;

/// <summary>Tabela orchestrator.TER — um registo por PDA/dispositivo.</summary>
public class TerminalEntity
{
    public string Id { get; set; } = null!;
    public string Codigo { get; set; } = null!;
    public string? Descricao { get; set; }
    public bool Ativo { get; set; } = true;
    public DateTime? UltimoAcessoEm { get; set; }
}
