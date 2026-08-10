using Microsoft.EntityFrameworkCore;
using Orchestrator.Api.Data;
using Orchestrator.Api.Data.Entities;

namespace Orchestrator.Api.Tipificacao;

/// <summary>Estado da ficha de um artigo (Anexo A.6).</summary>
public enum QualidadeFicha
{
    OK,
    SEM_FICHA,
    SEM_EMB,
    SEM_DIMS,
    SEM_PESO,
    SEM_CLASSE,
}

/// <summary>Volume/peso cubicado de uma linha de PS (Anexo A.1).</summary>
public record CubicagemLinha(string Sku, int Quantidade, decimal VolumeCm3, QualidadeFicha Ficha);

/// <summary>Volume/peso agregado de uma Ordem de Preparação (Anexo A.2).</summary>
public record CubicagemOrdem(
    decimal VolumeCm3,
    decimal PesoKg,
    int NRefs,
    int NLinhasNaoCubicaveis,
    IReadOnlyList<CubicagemLinha> Linhas)
{
    public decimal VolumeLitros => VolumeCm3 / 1000m;
}

/// <summary>Resultado da tipificação (Anexo A.4/A.5): tipo indicativo e, se multi-plataforma, o número de plataformas.</summary>
public record ResultadoTipificacao(string? TipoCodigo, string Notacao, int NPlataformas);

/// <summary>Uma camada de empilhamento atribuída a uma plataforma (Anexo A.8).</summary>
public record Camada(int Indice, string Classe);

/// <summary>
/// Implementa as regras de cubicagem e tipificação do Anexo A do
/// documento de requisitos v0.4 (ADR-015). Todos os limiares de volume
/// vêm de <c>TiposPlataforma</c> (parâmetro de configuração, não
/// constante de código — regra explícita de A.1/A.4).
/// </summary>
public class CubicagemService(WopaDbContext db)
{
    // Anexo A.1 — cubicagem de uma linha de PS.
    public static CubicagemLinha CubicarLinha(ArtigoEntity? artigo, string sku, int quantidade)
    {
        if (artigo is null)
            return new CubicagemLinha(sku, quantidade, 0m, QualidadeFicha.SEM_FICHA);

        var ficha = Avaliar(artigo);
        if (ficha is QualidadeFicha.SEM_EMB or QualidadeFicha.SEM_DIMS or QualidadeFicha.SEM_FICHA)
            return new CubicagemLinha(sku, quantidade, 0m, ficha);

        var volCaixa = artigo.ComprimentoCaixaCm!.Value * artigo.LarguraCaixaCm!.Value * artigo.AlturaCaixaCm!.Value;
        var unidadesPorCaixa = artigo.UnidadesPorCaixa!.Value;
        var caixasCompletas = quantidade / unidadesPorCaixa;
        var avulsas = quantidade % unidadesPorCaixa;
        var volLinha = (caixasCompletas + (decimal)avulsas / unidadesPorCaixa) * volCaixa;

        return new CubicagemLinha(sku, quantidade, volLinha, ficha);
    }

    // Anexo A.6 — qualidade da ficha de artigo, por ordem de precedência.
    public static QualidadeFicha Avaliar(ArtigoEntity artigo)
    {
        if (artigo.UnidadesPorCaixa is null or <= 0) return QualidadeFicha.SEM_EMB;
        if (artigo.ComprimentoCaixaCm is null or <= 0
            || artigo.LarguraCaixaCm is null or <= 0
            || artigo.AlturaCaixaCm is null or <= 0) return QualidadeFicha.SEM_DIMS;
        if (artigo.PesoUnitarioKg is null or <= 0) return QualidadeFicha.SEM_PESO;
        if (string.IsNullOrWhiteSpace(artigo.ClasseEmpilhamento)) return QualidadeFicha.SEM_CLASSE;
        return QualidadeFicha.OK;
    }

    // Anexo A.2 — volume de picking de uma Ordem de Preparação: soma das
    // linhas de todos os PS que a compõem. Versão async: carrega os
    // Artigos necessários (1 round-trip). Para listas de várias ordens,
    // usa a sobrecarga síncrona com um dicionário já carregado — ver
    // CubicarOrdem — para não repetir a consulta por ordem (N+1).
    public async Task<CubicagemOrdem> CubicarOrdemAsync(IReadOnlyList<OrdemSeparacaoLinhaEntity> linhasPs)
    {
        var skus = linhasPs.Select(l => l.Sku).Distinct().ToList();
        var artigos = await db.Artigos.Where(a => skus.Contains(a.Sku)).ToDictionaryAsync(a => a.Sku);
        return CubicarOrdem(linhasPs, artigos);
    }

    // Versão pura/síncrona (sem acesso a BD) — para quando o chamador já
    // tem os Artigos carregados (ex.: listar muitas ordens de uma vez).
    public static CubicagemOrdem CubicarOrdem(IReadOnlyList<OrdemSeparacaoLinhaEntity> linhasPs, IReadOnlyDictionary<string, ArtigoEntity> artigosPorSku)
    {
        var skus = linhasPs.Select(l => l.Sku).Distinct().ToList();

        var linhas = linhasPs
            .Select(l => CubicarLinha(artigosPorSku.GetValueOrDefault(l.Sku), l.Sku, l.Quantidade))
            .ToList();

        var pesoTotal = linhasPs.Sum(l =>
            artigosPorSku.TryGetValue(l.Sku, out var a) && a.PesoUnitarioKg is { } peso ? peso * l.Quantidade : 0m);

        return new CubicagemOrdem(
            VolumeCm3: linhas.Sum(l => l.VolumeCm3),
            PesoKg: pesoTotal,
            NRefs: skus.Count,
            NLinhasNaoCubicaveis: linhas.Count(l => l.Ficha != QualidadeFicha.OK),
            Linhas: linhas);
    }

    // Anexo A.4/A.5 — escolhe o menor cesto onde o volume cabe; acima da
    // maior capacidade, decompõe em multi-plataforma P1(n). vol_ordem = 0
    // nunca é interpretado como "cabe no menor cesto" (A.4). Versão async:
    // carrega TiposPlataforma (1 round-trip); para listas, usa a
    // sobrecarga síncrona com os tipos já carregados.
    public async Task<ResultadoTipificacao> TipificarAsync(decimal volumeCm3)
    {
        var tipos = await db.TiposPlataforma.OrderBy(t => t.CapacidadeUtilLitros).ToListAsync();
        return Tipificar(volumeCm3, tipos);
    }

    // Versão pura/síncrona — tipos já carregados e ordenados por
    // capacidade ascendente (ver TiposPlataformaOrdenadosAsync).
    public static ResultadoTipificacao Tipificar(decimal volumeCm3, IReadOnlyList<TipoPlataformaEntity> tiposOrdenados)
    {
        if (tiposOrdenados.Count == 0)
            throw new InvalidOperationException("Não existem tipos de plataforma configurados.");

        if (volumeCm3 <= 0)
            return new ResultadoTipificacao(null, "SEM_TIPO", 0);

        var volumeLitros = volumeCm3 / 1000m;
        var menor = tiposOrdenados.FirstOrDefault(t => volumeLitros <= t.CapacidadeUtilLitros);
        if (menor is not null)
            return new ResultadoTipificacao(menor.Codigo, menor.Codigo, 1);

        // Excedente: sempre plataformas do maior tipo (P1 por convenção do
        // cliente — simplicidade operacional, mesmo quando o resto caberia
        // num cesto menor).
        var maior = tiposOrdenados[^1];
        var nPlataformas = (int)Math.Ceiling(volumeLitros / maior.CapacidadeUtilLitros);
        return new ResultadoTipificacao(maior.Codigo, $"{maior.Codigo}({nPlataformas})", nPlataformas);
    }

    // Helper para quem vai chamar Tipificar(...) em massa (evita repetir
    // o ORDER BY por chamada).
    public async Task<IReadOnlyList<TipoPlataformaEntity>> TiposPlataformaOrdenadosAsync() =>
        await db.TiposPlataforma.OrderBy(t => t.CapacidadeUtilLitros).ToListAsync();

    // Anexo A.8 — padrão de empilhamento cíclico (1 camada pesada + N
    // leves). Limiares de altura ilustrativos, não validados pelo
    // cliente (o próprio documento os assinala como "DECISÃO PENDENTE").
    public static IReadOnlyList<Camada> SequenciaCamadas(int nPlataformas, decimal? alturaPaleteCm)
    {
        var n = alturaPaleteCm switch
        {
            null => 2,
            <= 140m => 2,
            _ => 3,
        };

        var camadas = new List<Camada>(nPlataformas);
        for (var i = 1; i <= nPlataformas; i++)
        {
            var posicaoNoCiclo = (i - 1) % (n + 1);
            camadas.Add(new Camada(i, posicaoNoCiclo == 0 ? "Pesada" : "Leve"));
        }
        return camadas;
    }
}
