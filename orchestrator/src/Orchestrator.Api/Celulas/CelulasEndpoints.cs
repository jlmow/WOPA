using Microsoft.EntityFrameworkCore;
using Orchestrator.Api.Data;

namespace Orchestrator.Api.Celulas;

public record CelulaDto(string Id, string Codigo, string Nome, int CapacidadeDiariaUnidades, bool Ativa);

/// <summary>Carga vs. capacidade de uma célula num dia (ADR-027) — "unidades" é uma métrica simples e provisória (soma de QuantidadeAlvo), por afinar com histórico real.</summary>
public record CargaCelulaDto(string CelulaId, string Codigo, string Nome, int CapacidadeDiariaUnidades, int CargaUnidades);

/// <summary>
/// Célula = recurso de capacidade (packing/montagem/consolidação),
/// ADR-027. Capacidade por dia é o requisito-chave saído da reunião de
/// planeamento com o cliente: o supervisor precisa de ver, por célula e
/// por dia, quanto já está comprometido vs. quanto cabe.
/// </summary>
public static class CelulasEndpoints
{
    public static void MapCelulasEndpoints(this WebApplication app)
    {
        var group = app.MapGroup("/api/celulas").WithTags("Celulas");

        group.MapGet("/", async (WopaDbContext db) =>
        {
            var celulas = await db.Celulas.Where(c => c.Ativa).OrderBy(c => c.Codigo).ToListAsync();
            return celulas.Select(c => new CelulaDto(c.Id, c.Codigo, c.Nome, c.CapacidadeDiariaUnidades, c.Ativa));
        })
        .WithName("ListarCelulas");

        // Carga do dia (ADR-027): soma de QuantidadeAlvo das MissaoLinhas
        // de Missões atribuídas a cada célula, com DataPlaneada == data
        // pedida, ou sem DataPlaneada mas criadas nesse dia (despacho
        // imediato, sem agendamento). Painel de capacidade do controller.
        group.MapGet("/carga", async (DateOnly data, WopaDbContext db) =>
        {
            var celulas = await db.Celulas.Where(c => c.Ativa).OrderBy(c => c.Codigo).ToListAsync();

            var missoesDoDia = await db.Missoes
                .Where(m => m.CelulaId != null && m.Estado != "FechadaIncompleta"
                    && ((m.DataPlaneada != null && m.DataPlaneada == data)
                        || (m.DataPlaneada == null && m.CriadaEm.Date == data.ToDateTime(TimeOnly.MinValue))))
                .ToListAsync();

            var cargaPorCelula = new Dictionary<string, int>();
            foreach (var missao in missoesDoDia)
            {
                var unidades = await db.MissaoLinhas.Where(l => l.MissaoId == missao.Id).SumAsync(l => (int?)l.QuantidadeAlvo) ?? 0;
                cargaPorCelula[missao.CelulaId!] = cargaPorCelula.GetValueOrDefault(missao.CelulaId!) + unidades;
            }

            return celulas.Select(c => new CargaCelulaDto(
                c.Id, c.Codigo, c.Nome, c.CapacidadeDiariaUnidades, cargaPorCelula.GetValueOrDefault(c.Id)));
        })
        .WithName("ObterCargaCelulas");
    }
}
