using Microsoft.EntityFrameworkCore;
using Orchestrator.Api.Data;
using Orchestrator.Api.Data.Entities;

namespace Orchestrator.Api.Picking;

public record ScanRequest(string Barcode, string? OperacaoId = null);

public record ConfirmRequest(string? OperacaoId = null);

public record PickRequest(string AlveoloId, int Quantidade, string? OperacaoId = null);

public record ErrorResponse(string Erro);

public record MissionSummary(string Codigo, int TotalLinhas, int LinhasConcluidas);

/// <summary>Um alvéolo com stock do artigo da tarefa, na zona onde o operador está (RF-PIC).</summary>
public record AlveoloComStock(string AlveoloId, string Codigo, int QuantidadeDisponivel, int SugestaoQuantidade);

public static class PickingEndpoints
{
    public static void MapPickingEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/picking").WithTags("Picking");

        group.MapGet("/tasks", async (WopaDbContext db) =>
        {
            var missao = await ObterOuAtribuirMissaoAtualAsync(db);
            if (missao is null) return Results.Ok(Array.Empty<PickingTask>());

            var linhas = await db.MissaoLinhas
                .Include(l => l.Alveolo)
                .Where(l => l.MissaoId == missao.Id)
                .OrderBy(l => l.Alveolo!.Codigo)
                .ToListAsync();
            return Results.Ok(linhas.Select(ParaDto));
        })
        .WithName("ListarTarefasPicking");

        group.MapGet("/mission", async (WopaDbContext db) =>
        {
            // "Próxima missão" (ADR-008/011): a mais antiga ainda não
            // concluída/fechada, entre os centros de trabalho Picking.
            // Atribuição por operador/zona/dispositivo continua por
            // decidir (ver ARCHITECTURE.md secção 8) — nesta PoC há sempre
            // no máximo uma missão de picking ativa, o que já cumpre o
            // "uma missão de cada vez" do ADR-008.
            var missao = await ObterOuAtribuirMissaoAtualAsync(db);
            if (missao is null)
                return Results.NotFound(new ErrorResponse("Sem missão de picking disponível."));

            var total = await db.MissaoLinhas.CountAsync(l => l.MissaoId == missao.Id);
            var concluidas = await db.MissaoLinhas.CountAsync(l =>
                l.MissaoId == missao.Id && l.Estado == PickingTaskStatus.Concluida);
            return Results.Ok(new MissionSummary(missao.Codigo, total, concluidas));
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

            // A leitura do código de barras já não incrementa a quantidade
            // diretamente (ver ADR-022) -- só confirma que o operador está no
            // artigo certo e desbloqueia o passo seguinte (escolher alvéolo +
            // quantidade, endpoint /pick). A quantidade lida só muda lá.
            if (task.Estado == PickingTaskStatus.Pendente)
                task.Estado = PickingTaskStatus.EmProgresso;

            // A.13: a primeira leitura de uma missão atribuída marca o
            // início real da execução (distinto de "atribuída").
            var missao = await db.Missoes.SingleAsync(m => m.Id == task.MissaoId);
            if (missao.Estado == "Atribuida")
            {
                missao.Estado = "EmExecucao";
                missao.IniciadaEm = DateTime.UtcNow;
            }

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

        // RF-PIC/ADR-022: lista de alvéolos com stock do artigo da tarefa, na
        // zona da missão -- o operador tem de escolher um destes (não há
        // alvéolo fixo à partida). SugestaoQuantidade é a falta da missão,
        // limitada ao que está disponível nesse alvéolo -- o operador pode
        // sempre alterar no ecrã.
        group.MapGet("/tasks/{id}/alveolos", async (string id, WopaDbContext db) =>
        {
            var task = await db.MissaoLinhas.SingleOrDefaultAsync(l => l.Id == id);
            if (task is null) return Results.NotFound();

            var missao = await db.Missoes.SingleAsync(m => m.Id == task.MissaoId);
            if (missao.ZonaId is null)
                return Results.Ok(Array.Empty<AlveoloComStock>());

            var falta = task.QuantidadeAlvo - task.QuantidadeLida;
            var opcoes = await db.Estoque
                .Include(e => e.Alveolo)
                .Where(e => e.Sku == task.Sku && e.Quantidade > 0 && e.Alveolo!.ZonaId == missao.ZonaId)
                .OrderByDescending(e => e.Quantidade)
                .Select(e => new AlveoloComStock(e.AlveoloId, e.Alveolo!.Codigo, e.Quantidade, Math.Min(falta, e.Quantidade)))
                .ToListAsync();

            return Results.Ok(opcoes);
        })
        .WithName("ListarAlveolosComStockPicking");

        // RF-PIC/ADR-022: regista a quantidade separada num alvéolo escolhido
        // pelo operador -- decrementa SA, regista o movimento em SL (CM=501,
        // "Saída por picking") e soma à quantidade lida da tarefa. Uma
        // tarefa pode precisar de vários picks (alvéolos diferentes) até
        // atingir QuantidadeAlvo; o /confirm continua a ser o passo
        // separado que fecha a tarefa, como antes.
        group.MapPost("/tasks/{id}/pick", async (string id, PickRequest request, WopaDbContext db) =>
        {
            if (request.OperacaoId is { } opId && await db.OperacoesProcessadas.AnyAsync(o => o.OperacaoId == opId))
            {
                var jaProcessada = await db.MissaoLinhas.Include(l => l.Alveolo).SingleAsync(l => l.Id == id);
                return Results.Ok(ParaDto(jaProcessada));
            }

            if (request.Quantidade <= 0)
                return Results.BadRequest(new ErrorResponse("A quantidade tem de ser maior que zero."));

            var task = await db.MissaoLinhas.Include(l => l.Alveolo).SingleOrDefaultAsync(l => l.Id == id);
            if (task is null) return Results.NotFound();

            if (task.Estado == PickingTaskStatus.Concluida)
                return Results.Conflict(new ErrorResponse("Tarefa já concluída."));

            if (task.QuantidadeLida + request.Quantidade > task.QuantidadeAlvo)
                return Results.Conflict(new ErrorResponse(
                    $"Essa quantidade excede a necessidade da missão (faltam {task.QuantidadeAlvo - task.QuantidadeLida})."));

            var estoque = await db.Estoque.SingleOrDefaultAsync(e => e.Sku == task.Sku && e.AlveoloId == request.AlveoloId);
            if (estoque is null || estoque.Quantidade < request.Quantidade)
                return Results.Conflict(new ErrorResponse("Stock insuficiente nesse alvéolo."));

            estoque.Quantidade -= request.Quantidade;
            estoque.AtualizadoEm = DateTime.UtcNow;

            db.MovimentosStock.Add(new MovimentoStockEntity
            {
                CodigoMovimentoId = 501,
                Sku = task.Sku,
                AlveoloId = request.AlveoloId,
                Quantidade = request.Quantidade,
                MissaoLinhaId = task.Id,
                CriadoEm = DateTime.UtcNow,
            });

            task.QuantidadeLida += request.Quantidade;
            if (task.Estado == PickingTaskStatus.Pendente)
                task.Estado = PickingTaskStatus.EmProgresso;

            var missao = await db.Missoes.SingleAsync(m => m.Id == task.MissaoId);
            if (missao.Estado == "Atribuida")
            {
                missao.Estado = "EmExecucao";
                missao.IniciadaEm = DateTime.UtcNow;
            }

            if (request.OperacaoId is { } novoOpId)
                db.OperacoesProcessadas.Add(new OperacaoProcessadaEntity
                {
                    OperacaoId = novoOpId,
                    MissaoLinhaId = task.Id,
                    Tipo = "pick",
                });

            await db.SaveChangesAsync();
            return Results.Ok(ParaDto(task));
        })
        .WithName("RegistarPickPicking");

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

            // A.13: quando a última linha da missão fica concluída, a
            // própria missão fecha e regista quando terminou.
            var todasConcluidas = !await db.MissaoLinhas
                .AnyAsync(l => l.MissaoId == task.MissaoId && l.Id != task.Id && l.Estado != PickingTaskStatus.Concluida);
            if (todasConcluidas)
            {
                var missao = await db.Missoes.SingleAsync(m => m.Id == task.MissaoId);
                missao.Estado = "Concluida";
                missao.ConcluidaEm = DateTime.UtcNow;
            }

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
                missao.Estado = "Atribuida";
                missao.MotivoPausa = null;
                missao.AtribuidaEm = DateTime.UtcNow;
                missao.IniciadaEm = null;
                missao.PausadaEm = null;
                missao.RetomadaEm = null;
                missao.ConcluidaEm = null;
            }

            db.OperacoesProcessadas.RemoveRange(db.OperacoesProcessadas);
            await db.SaveChangesAsync();

            return Results.Ok(linhas.Select(ParaDto));
        })
        .WithName("ResetPickingPoc");
    }

    // "Uma missão de cada vez" (ADR-008): a mais antiga entre as ainda não
    // concluídas/fechadas do centro de trabalho Picking. Atribui-a
    // automaticamente (Criada -> Atribuida) na primeira vez que é pedida.
    private static async Task<MissaoEntity?> ObterOuAtribuirMissaoAtualAsync(WopaDbContext db)
    {
        var missao = await db.Missoes
            .Where(m => m.CentroTrabalho == "Picking" && m.Estado != "Concluida" && m.Estado != "FechadaIncompleta")
            .OrderBy(m => m.CriadaEm)
            .FirstOrDefaultAsync();
        if (missao is null) return null;

        if (missao.Estado == "Criada")
        {
            missao.Estado = "Atribuida";
            missao.AtribuidaEm = DateTime.UtcNow;
            await db.SaveChangesAsync();
        }

        return missao;
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
        // Sem Alveolo (ex.: linha do Armazém Automático — sem detalhe de
        // alvéolo, ver ARCHITECTURE.md secção 4.6): "" por agora. Ainda não
        // está decidido se estas linhas sequer chegam ao ecrã do pda-picking
        // (pode ser uma zona sem operação humana) — por implementar.
        Localizacao = linha.Alveolo?.Codigo ?? string.Empty,
        Plataforma = linha.Plataforma,
        QuantidadeAlvo = linha.QuantidadeAlvo,
        QuantidadeLida = linha.QuantidadeLida,
        Estado = linha.Estado,
    };
}
