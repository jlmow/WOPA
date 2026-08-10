namespace Orchestrator.Api.Data.Entities;

/// <summary>
/// Tabela US — operadores/utilizadores. Login universal (ver
/// ARCHITECTURE.md): todo o software WOPA (PDA ou Windows) tem de
/// começar por um ecrã de login user+PIN — ainda não validado a sério
/// em nenhum frontend (o pda pede o número mas não confirma o PIN).
/// </summary>
public class UtilizadorEntity
{
    public string Id { get; set; } = null!;
    public string NumeroOperador { get; set; } = null!;

    /// <summary>PIN em texto por agora (PoC) — hash antes de produção, ver ARCHITECTURE.md secção 8.</summary>
    public string Pin { get; set; } = null!;

    public string Nome { get; set; } = null!;
    public bool Ativo { get; set; } = true;
}
