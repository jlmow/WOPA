namespace Orchestrator.Api.Data.Entities;

/// <summary>Tabela orchestrator.US — operadores.</summary>
public class UtilizadorEntity
{
    public string Id { get; set; } = null!;
    public string NumeroOperador { get; set; } = null!;
    public string Nome { get; set; } = null!;
    public bool Ativo { get; set; } = true;
}
