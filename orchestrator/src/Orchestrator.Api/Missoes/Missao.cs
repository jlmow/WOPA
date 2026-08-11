namespace Orchestrator.Api.Missoes;

public record MissaoResumo(
    string Id,
    string Codigo,
    string CentroTrabalho,
    string? ZonaId,
    string? PlataformaCodigo,
    bool PlataformaConfirmada,
    string? UtilizadorId,
    string Estado,
    string? MotivoPausa,
    DateTime CriadaEm,
    DateTime? AtribuidaEm,
    DateTime? IniciadaEm,
    DateTime? PausadaEm,
    DateTime? ConcluidaEm,
    int TotalLinhas,
    int LinhasConcluidas);

public record PausarRequest(string Motivo);

public record ReatribuirRequest(string? UtilizadorId, string? TerminalId);
