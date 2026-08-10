using Microsoft.EntityFrameworkCore;
using Orchestrator.Api.Data;
using Orchestrator.Api.Data.Entities;

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

        group.MapGet("/tasks", async (WopaDbContext db) =>
        {
            var linhas = await db.MissaoLinhas
                .Include(l => l.Alveolo)
                .OrderBy(l => l.Alveolo!.Codigo)
                .ToListAsync();
            return linhas.Select(ParaDto);
        })
        .WithName("ListarTarefasPicking");

        group.MapGet("/mission", async (WopaDbContext db) =>
        {
            // PoC: só existe uma missão (ADR-008: "próxima missão" ainda por
            // implementar — falta o motor que cria missões a partir das
            // Ordens de Separação, ver ADR-011).
            var missao = await db.Missoes.FirstAsync();
            var total = await db.MissaoLinhas.CountAsync(l => l.MissaoId == missao.Id);
            var concluidas = await db.MissaoLinhas.CountAsync(l =>
                l.MissaoId == missao.Id && l.Estado == PickingTaskStatus.Concluida);
            return new MissionSummary(missao.Codigo, total, concluidas);
        })
        .WithName("ObterResumoMissaoPicking");

        group.MapGet("/tasks/{id}", async (string id, WopaDbContext db) =>
        {
            var linha = await db.MissaoLinhas.Include(l => l.Alveolo).SingleOrDefaultAsync(l => l.Id == id);
            return linha is not null ? Results.Ok(ParaDto(linha)) : Results.NotFound();
        })
        .WithName("ObterTarefaPicking");

        group.MapPost("/tasks/{id}/scan", async (string id, ScanRequest request, WopaDbContext db) =>
        {
            // ADR-007: um PDA que esteve offline pode reenviar a mesma leitura
            // ao sincronizar (ex.: a resposta anterior perdeu-se em trânsito).
            // Com o mesmo operacaoId, devolvemos o estado atual da linha em
            // vez de aplicar a leitura outra vez — não precisamos de guardar
            // um snapshot à parte, o registo em OperacoesProcessadas já basta
            // para saber que esta operação específica já foi aplicada.
            if (request.OperacaoId is { } opId && await db.OperacoesProcessadas.AnyAsync(o => o.OperacaoId == opId))
            {
                var jaProcessada = await db.MissaoLinhas.Include(l => l.Alveolo).SingleAsync(l => l.Id == id);
                return Results.Ok(ParaDto(jaProcessada));
            }

            var task = await db.MissaoLinhas.Include(l => l.Alveolo).SingleOrDefaultAsync(l => l.Id == id);
            if (task is null)
                return Results.NotFound();

            if (task.Estado == PickingTaskStatus.Concluida)
                return Results.Conflict(new ErrorResponse("Tarefa já concluída."));

            if (!string.Equals(task.CodigoBarras, request.Barcode, StringComparison.Ordinal))
                return Results.Conflict(new ErrorResponse("Código de barras não corresponde ao artigo esperado."));

            task.QuantidadeLida = Math.Min(task.QuantidadeLida + 1, task.QuantidadeAlvo);
            task.Estado = PickingTaskStatus.EmProgresso;

            if (request.OperacaoId is { } novoOpId)
                db.OperacoesProcessadas.Add(new OperacaoProcessadaEntity
                {
                    OperacaoId = novoOpId,
                    MissaoLinhaId = task.Id,
                    Tipo = "scan",
                });

            await db.SaveChangesAsync();
            return Results.Ok(ParaDto(task));
        })
        .WithName("RegistarLeituraPicking");

        group.MapPost("/tasks/{id}/confirm", async (string id, ConfirmRequest request, WopaDbContext db) =>
        {
            if (request.OperacaoId is { } opId && await db.OperacoesProcessadas.AnyAsync(o => o.OperacaoId == opId))
            {
                var jaProcessada = await db.MissaoLinhas.Include(l => l.Alveolo).SingleAsync(l => l.Id == id);
                return Results.Ok(ParaDto(jaProcessada));
            }

            var task = await db.MissaoLinhas.Include(l => l.Alveolo).SingleOrDefaultAsync(l => l.Id == id);
            if (task is null)
                return Results.NotFound();

            if (task.QuantidadeLida < task.QuantidadeAlvo)
                return Results.Conflict(new ErrorResponse(
                    $"Ainda faltam {task.QuantidadeAlvo - task.QuantidadeLida} leitura(s) antes de confirmar."));

            task.Estado = PickingTaskStatus.Concluida;

            if (request.OperacaoId is { } novoOpId)
                db.OperacoesProcessadas.Add(new OperacaoProcessadaEntity
                {
                    OperacaoId = novoOpId,
                    MissaoLinhaId = task.Id,
                    Tipo = "confirm",
                });

            await db.SaveChangesAsync();
            return Results.Ok(ParaDto(task));
        })
        .WithName("ConfirmarTarefaPicking");

        // Endpoint de apoio só para a PoC/testes: repor os dados de exemplo.
        group.MapPost("/reset", async (WopaDbContext db) =>
        {
            var linhas = await db.MissaoLinhas.Include(l => l.Alveolo).ToListAsync();
            foreach (var linha in linhas)
            {
                linha.QuantidadeLida = 0;
                linha.Estado = PickingTaskStatus.Pendente;
            }

            var missoes = await db.Missoes.ToListAsync();
            foreach (var missao in missoes)
            {
                missao.Estado = "Pendente";
                missao.ConcluidaEm = null;
            }

            db.OperacoesProcessadas.RemoveRange(db.OperacoesProcessadas);
            await db.SaveChangesAsync();

            return Results.Ok(linhas.Select(ParaDto));
        })
        .WithName("ResetPickingPoc");
    }

    // Opção A (ARCHITECTURE.md ADR-012): a API pública mantém o formato
    // simples que o pda já consome e tem testado — localizacao/plataforma
    // como texto — mesmo com o schema normalizado (AlveoloId, etc.) por
    // trás. O join para Alveolo.Codigo acontece só aqui.
    private static PickingTask ParaDto(MissaoLinhaEntity linha) => new()
    {
        Id = linha.Id,
        Sku = linha.Sku,
        Descricao = linha.Descricao,
        CodigoBarras = linha.CodigoBarras,
        Localizacao = linha.Alveolo!.Codigo,
        Plataforma = linha.Plataforma,
        QuantidadeAlvo = linha.QuantidadeAlvo,
        QuantidadeLida = linha.QuantidadeLida,
        Estado = linha.Estado,
    };
}
