using Microsoft.EntityFrameworkCore;
using Orchestrator.Api.Data;
using Orchestrator.Api.Data.Entities;

namespace Orchestrator.Api.Picking;

public record ScanRequest(string Barcode, string? OperacaoId = null);

public record ConfirmRequest(string? OperacaoId = null);

// Motivo (ADR-027): obrigatório no pda quando a quantidade difere da
// sugerida (ex.: "Falta de stock", "Caixa incompleta", "Dano") -- o
// servidor não valida isto (não sabe qual era a sugestão original sem a
// recalcular), a obrigatoriedade fica no ecrã do pda.
// MatriculaPalete (ADR-035): a palete de ORIGEM de onde o operador
// está mesmo a tirar o stock -- necessário porque um alvéolo pode ter
// mais do que uma palete do mesmo SKU (SA passa a ter chave (Sku,
// AlveoloId, PaleteId)); sem isto não há como saber de qual delas saiu.
public record PickRequest(string AlveoloId, string MatriculaPalete, int Quantidade, string? Motivo = null, string? OperacaoId = null);

public record ErrorResponse(string Erro);

// Gate de montagem (ADR-029): PrimeiraMontagem=true -> esta zona monta a
// plataforma de raiz (palete + N cestos vazios); false -> plataforma já
// vem montada de outra zona, só é preciso confirmar (mesma palete + cestos).
public record MontagemInfo(string PlataformaId, string TipoPlataformaCodigo, int CestosNecessarios, bool Confirmada, bool PrimeiraMontagem);

public record MissionSummary(string Id, string Codigo, int TotalLinhas, int LinhasConcluidas, MontagemInfo? Montagem);

public record MontagemRequest(string MatriculaPalete, string[] MatriculasCestos, string? OperacaoId = null);

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

            var montagem = await ObterMontagemInfoAsync(db, missao);
            return Results.Ok(new MissionSummary(missao.Id, missao.Codigo, total, concluidas, montagem));
        })
        .WithName("ObterResumoMissaoPicking");

        // Gate de montagem (ADR-029): sem plataforma indicada não há
        // picking de artigos. Primeira zona de uma Ordem monta a
        // plataforma de raiz (palete + N cestos, N vem de TiposPlataforma
        // -- 0 para P0); zonas seguintes só confirmam a mesma palete e os
        // mesmos cestos, sem os reler do zero.
        group.MapPost("/mission/{id}/montagem", async (string id, MontagemRequest request, WopaDbContext db) =>
        {
            var missao = await db.Missoes.SingleOrDefaultAsync(m => m.Id == id);
            if (missao is null) return Results.NotFound();

            // Reenvio (offline/retry): já confirmada, devolve sucesso sem repetir a validação.
            if (missao.PlataformaConfirmada)
                return Results.Ok(new { confirmada = true });

            if (missao.PlataformaId is null)
                return Results.Conflict(new ErrorResponse("Esta missão não tem plataforma associada."));

            var plataforma = await db.Plataformas.SingleAsync(p => p.Id == missao.PlataformaId);
            var tipo = await db.TiposPlataforma.SingleAsync(t => t.Codigo == plataforma.TipoPlataformaCodigo);

            if (string.IsNullOrWhiteSpace(request.MatriculaPalete))
                return Results.BadRequest(new ErrorResponse("Matrícula da palete em falta."));

            var cestosLidos = request.MatriculasCestos ?? Array.Empty<string>();
            if (cestosLidos.Length != tipo.CestosPorPlataforma)
                return Results.Conflict(new ErrorResponse(
                    $"São precisos {tipo.CestosPorPlataforma} cesto(s) para {tipo.Codigo} (foram lidos {cestosLidos.Length})."));

            // Duas leituras iguais rebentavam a UNIQUE de PlataformaCestos/
            // CestoInstancias mais abaixo (erro 500 em vez de mensagem
            // clara) -- e não faz sentido dois cestos físicos com a mesma
            // matrícula na mesma plataforma de qualquer forma.
            if (cestosLidos.Distinct(StringComparer.Ordinal).Count() != cestosLidos.Length)
                return Results.Conflict(new ErrorResponse("As matrículas dos cestos têm de ser todas diferentes."));

            // ADR-035: as matrículas são pré-carregadas (ecrã do controller),
            // não inventadas ao ler -- valida contra o que já existe em vez
            // de criar instâncias novas na primeira leitura.
            var palete = await db.Paletes.SingleOrDefaultAsync(p => p.Matricula == request.MatriculaPalete);
            if (palete is null)
                return Results.Conflict(new ErrorResponse("Matrícula da palete desconhecida — regista-a primeiro no controller."));

            var cestosEncontrados = await db.CestoInstancias
                .Where(c => cestosLidos.Contains(c.Matricula))
                .ToListAsync();
            if (cestosEncontrados.Count != cestosLidos.Length)
            {
                var desconhecidos = cestosLidos.Except(cestosEncontrados.Select(c => c.Matricula), StringComparer.Ordinal);
                return Results.Conflict(new ErrorResponse(
                    $"Matrícula(s) de cesto desconhecida(s): {string.Join(", ", desconhecidos)} — regista-as primeiro no controller."));
            }

            if (plataforma.MontadaEm is null)
            {
                // Primeira zona desta Ordem: montagem de raiz.
                plataforma.PaleteId = palete.Id;
                plataforma.MontadaEm = DateTime.UtcNow;
                palete.LocalizacaoAtualId = null; // em circulação
                foreach (var cesto in cestosEncontrados)
                {
                    db.PlataformaCestos.Add(new PlataformaCestoEntity
                    {
                        Id = Guid.NewGuid().ToString("n"),
                        PlataformaId = plataforma.Id,
                        MatriculaCesto = cesto.Matricula,
                    });
                    cesto.Estado = "EmUso";
                    cesto.LocalizacaoAtualId = null;
                }
            }
            else
            {
                // Zona seguinte: só confirma que é a mesma plataforma (mesma palete + mesmos cestos).
                if (plataforma.PaleteId != palete.Id)
                    return Results.Conflict(new ErrorResponse("Matrícula da palete não corresponde à plataforma desta missão."));

                var matriculasConhecidas = await db.PlataformaCestos
                    .Where(c => c.PlataformaId == plataforma.Id)
                    .Select(c => c.MatriculaCesto)
                    .ToListAsync();
                if (!cestosLidos.OrderBy(c => c, StringComparer.Ordinal).SequenceEqual(matriculasConhecidas.OrderBy(c => c, StringComparer.Ordinal)))
                    return Results.Conflict(new ErrorResponse("Os cestos lidos não correspondem aos desta plataforma."));
            }

            missao.PlataformaConfirmada = true;
            missao.PlataformaConfirmadaEm = DateTime.UtcNow;

            await db.SaveChangesAsync();
            return Results.Ok(new { confirmada = true });
        })
        .WithName("MontarOuConfirmarPlataformaPicking");

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

            var missao = await db.Missoes.SingleAsync(m => m.Id == task.MissaoId);

            // Gate de montagem (ADR-029): sem plataforma montada/confirmada
            // não há leitura de artigos.
            if (missao.PlataformaId is not null && !missao.PlataformaConfirmada)
                return Results.Conflict(new ErrorResponse("É preciso montar/confirmar a plataforma antes de picar artigos."));

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

            // ADR-035: um alvéolo pode ter mais do que uma palete do mesmo
            // SKU -- soma-se aqui para a escolha de alvéolo continuar
            // simples (um por artigo); a palete específica só é pedida a
            // seguir, no scan de /pick.
            var falta = task.QuantidadeAlvo - task.QuantidadeLida;
            var opcoes = await db.Estoque
                .Include(e => e.Alveolo)
                .Where(e => e.Sku == task.Sku && e.Quantidade > 0 && e.Alveolo!.ZonaId == missao.ZonaId)
                .GroupBy(e => new { e.AlveoloId, Codigo = e.Alveolo!.Codigo })
                .Select(g => new AlveoloComStock(g.Key.AlveoloId, g.Key.Codigo, g.Sum(e => e.Quantidade), Math.Min(falta, g.Sum(e => e.Quantidade))))
                .OrderByDescending(o => o.QuantidadeDisponivel)
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

            var missao = await db.Missoes.SingleAsync(m => m.Id == task.MissaoId);
            if (missao.PlataformaId is not null && !missao.PlataformaConfirmada)
                return Results.Conflict(new ErrorResponse("É preciso montar/confirmar a plataforma antes de picar artigos."));

            if (task.Estado == PickingTaskStatus.Concluida)
                return Results.Conflict(new ErrorResponse("Tarefa já concluída."));

            if (task.QuantidadeLida + request.Quantidade > task.QuantidadeAlvo)
                return Results.Conflict(new ErrorResponse(
                    $"Essa quantidade excede a necessidade da missão (faltam {task.QuantidadeAlvo - task.QuantidadeLida})."));

            if (string.IsNullOrWhiteSpace(request.MatriculaPalete))
                return Results.BadRequest(new ErrorResponse("Matrícula da palete de origem em falta."));

            // ADR-035: a matrícula é pré-carregada, tal como no gate de
            // montagem -- recusa matrícula desconhecida em vez de assumir.
            var paleteOrigem = await db.Paletes.SingleOrDefaultAsync(p => p.Matricula == request.MatriculaPalete);
            if (paleteOrigem is null)
                return Results.Conflict(new ErrorResponse("Matrícula da palete desconhecida — regista-a primeiro no controller."));

            var estoque = await db.Estoque.SingleOrDefaultAsync(e =>
                e.Sku == task.Sku && e.AlveoloId == request.AlveoloId && e.PaleteId == paleteOrigem.Id);
            if (estoque is null || estoque.Quantidade < request.Quantidade)
                return Results.Conflict(new ErrorResponse("Stock insuficiente nessa palete."));

            estoque.Quantidade -= request.Quantidade;
            estoque.AtualizadoEm = DateTime.UtcNow;

            db.MovimentosStock.Add(new MovimentoStockEntity
            {
                CodigoMovimentoId = 501,
                Sku = task.Sku,
                AlveoloId = request.AlveoloId,
                PaleteId = paleteOrigem.Id,
                Quantidade = request.Quantidade,
                MissaoLinhaId = task.Id,
                Motivo = request.Motivo,
                PlataformaId = missao.PlataformaId,
                CriadoEm = DateTime.UtcNow,
            });

            task.QuantidadeLida += request.Quantidade;
            if (task.Estado == PickingTaskStatus.Pendente)
                task.Estado = PickingTaskStatus.EmProgresso;

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
                missao.PlataformaConfirmada = false;
                missao.PlataformaConfirmadaEm = null;
            }

            var plataformas = await db.Plataformas.ToListAsync();
            foreach (var plataforma in plataformas)
            {
                plataforma.PaleteId = null;
                plataforma.MontadaEm = null;
            }

            db.PlataformaCestos.RemoveRange(db.PlataformaCestos);
            db.OperacoesProcessadas.RemoveRange(db.OperacoesProcessadas);
            await db.SaveChangesAsync();

            return Results.Ok(linhas.Select(ParaDto));
        })
        .WithName("ResetPickingPoc");
    }

    // "Uma missão de cada vez" (ADR-008): a mais antiga entre as ainda não
    // concluídas/fechadas do centro de trabalho Picking. Atribui-a
    // automaticamente (Criada -> Atribuida) na primeira vez que é pedida.
    // ADR-027: uma Missão "Planeada" para um dia futuro (despacho com
    // data) fica de fora até o dia chegar -- a partir daí conta como
    // "Criada" para este efeito, sem transição de estado explícita
    // nenhuma (poupa um job/cron só para isto).
    private static async Task<MissaoEntity?> ObterOuAtribuirMissaoAtualAsync(WopaDbContext db)
    {
        var hoje = DateOnly.FromDateTime(DateTime.UtcNow);
        var missao = await db.Missoes
            .Where(m => m.CentroTrabalho == "Picking" && m.Estado != "Concluida" && m.Estado != "FechadaIncompleta"
                && (m.Estado != "Planeada" || m.DataPlaneada == null || m.DataPlaneada <= hoje))
            .OrderBy(m => m.CriadaEm)
            .FirstOrDefaultAsync();
        if (missao is null) return null;

        if (missao.Estado == "Criada" || missao.Estado == "Planeada")
        {
            missao.Estado = "Atribuida";
            missao.AtribuidaEm = DateTime.UtcNow;
            await db.SaveChangesAsync();
        }

        return missao;
    }

    // ADR-029: null quando a missão não tem plataforma associada (nada a
    // montar/confirmar) — mantém o gate opcional em vez de partir missões
    // antigas/sem plataforma.
    private static async Task<MontagemInfo?> ObterMontagemInfoAsync(WopaDbContext db, MissaoEntity missao)
    {
        if (missao.PlataformaId is not { } plataformaId) return null;

        var plataforma = await db.Plataformas.SingleAsync(p => p.Id == plataformaId);
        var tipo = await db.TiposPlataforma.SingleAsync(t => t.Codigo == plataforma.TipoPlataformaCodigo);
        return new MontagemInfo(plataforma.Id, tipo.Codigo, tipo.CestosPorPlataforma, missao.PlataformaConfirmada, plataforma.MontadaEm is null);
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
