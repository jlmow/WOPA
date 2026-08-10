namespace Orchestrator.Api.Picking;

public record ScanRequest(string Barcode);

public record ErrorResponse(string Erro);

public static class PickingEndpoints
{
    public static void MapPickingEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/picking").WithTags("Picking");

        group.MapGet("/tasks", (PickingStore store) => store.GetAll())
            .WithName("ListarTarefasPicking");

        group.MapGet("/tasks/{id}", (string id, PickingStore store) =>
            store.Get(id) is { } task ? Results.Ok(task) : Results.NotFound())
            .WithName("ObterTarefaPicking");

        group.MapPost("/tasks/{id}/scan", (string id, ScanRequest request, PickingStore store) =>
        {
            var task = store.Get(id);
            if (task is null)
                return Results.NotFound();

            if (task.Estado == PickingTaskStatus.Concluida)
                return Results.Conflict(new ErrorResponse("Tarefa já concluída."));

            if (!string.Equals(task.CodigoBarras, request.Barcode, StringComparison.Ordinal))
                return Results.Conflict(new ErrorResponse("Código de barras não corresponde ao artigo esperado."));

            task.QuantidadeLida = Math.Min(task.QuantidadeLida + 1, task.QuantidadeAlvo);
            task.Estado = PickingTaskStatus.EmProgresso;

            return Results.Ok(task);
        })
        .WithName("RegistarLeituraPicking");

        group.MapPost("/tasks/{id}/confirm", (string id, PickingStore store) =>
        {
            var task = store.Get(id);
            if (task is null)
                return Results.NotFound();

            if (task.QuantidadeLida < task.QuantidadeAlvo)
                return Results.Conflict(new ErrorResponse(
                    $"Ainda faltam {task.QuantidadeAlvo - task.QuantidadeLida} leitura(s) antes de confirmar."));

            task.Estado = PickingTaskStatus.Concluida;
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
