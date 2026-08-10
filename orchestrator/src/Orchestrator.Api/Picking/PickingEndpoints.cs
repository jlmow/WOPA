namespace Orchestrator.Api.Picking;

public record ScanRequest(string Barcode, string? OperacaoId = null);

public record ConfirmRequest(string? OperacaoId = null);

public record ErrorResponse(string Erro);

public record MissionSummary(string Codigo, int TotalLinhas, int LinhasConcluidas);

public static class PickingEndpoints
{
    public static void MapPickingEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/picking").WithTags("Picking");

        group.MapGet("/tasks", (PickingStore store) => store.GetAll())
            .WithName("ListarTarefasPicking");

        group.MapGet("/mission", (PickingStore store) =>
        {
            var linhas = store.GetAll().ToList();
            return new MissionSummary(
                PickingStore.MissionCodigo,
                linhas.Count,
                linhas.Count(t => t.Estado == PickingTaskStatus.Concluida));
        })
        .WithName("ObterResumoMissaoPicking");

        group.MapGet("/tasks/{id}", (string id, PickingStore store) =>
            store.Get(id) is { } task ? Results.Ok(task) : Results.NotFound())
            .WithName("ObterTarefaPicking");

        group.MapPost("/tasks/{id}/scan", (string id, ScanRequest request, PickingStore store) =>
        {
            // ADR-007: um PDA que esteve offline pode reenviar a mesma leitura
            // ao sincronizar (ex.: a resposta anterior perdeu-se em trânsito).
            // Com o mesmo operacaoId, devolvemos o resultado já processado em
            // vez de aplicar a leitura outra vez.
            if (request.OperacaoId is { } opId && store.TryGetResultadoProcessado(opId, out var jaProcessado))
                return Results.Ok(jaProcessado);

            var task = store.Get(id);
            if (task is null)
                return Results.NotFound();

            if (task.Estado == PickingTaskStatus.Concluida)
                return Results.Conflict(new ErrorResponse("Tarefa já concluída."));

            if (!string.Equals(task.CodigoBarras, request.Barcode, StringComparison.Ordinal))
                return Results.Conflict(new ErrorResponse("Código de barras não corresponde ao artigo esperado."));

            task.QuantidadeLida = Math.Min(task.QuantidadeLida + 1, task.QuantidadeAlvo);
            task.Estado = PickingTaskStatus.EmProgresso;

            if (request.OperacaoId is { } novoOpId)
                store.RegistarResultadoProcessado(novoOpId, task);

            return Results.Ok(task);
        })
        .WithName("RegistarLeituraPicking");

        group.MapPost("/tasks/{id}/confirm", (string id, ConfirmRequest request, PickingStore store) =>
        {
            if (request.OperacaoId is { } opId && store.TryGetResultadoProcessado(opId, out var jaProcessado))
                return Results.Ok(jaProcessado);

            var task = store.Get(id);
            if (task is null)
                return Results.NotFound();

            if (task.QuantidadeLida < task.QuantidadeAlvo)
                return Results.Conflict(new ErrorResponse(
                    $"Ainda faltam {task.QuantidadeAlvo - task.QuantidadeLida} leitura(s) antes de confirmar."));

            task.Estado = PickingTaskStatus.Concluida;

            if (request.OperacaoId is { } novoOpId)
                store.RegistarResultadoProcessado(novoOpId, task);

            return Results.Ok(task);
        })
        .WithName("ConfirmarTarefaPicking");

        // Endpoint de apoio só para a PoC: repor os dados de exemplo.
        group.MapPost("/reset", (PickingStore store) =>
        {
            store.Reset();
            return Results.Ok(store.GetAll());
        })
        .WithName("ResetPickingPoc");
    }
}
