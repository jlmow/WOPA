namespace Orchestrator.Api.Config;

/// <summary>
/// Regras de negócio que governam como o controller monta missões a partir
/// das Ordens de Preparação. Conjunto básico de propostas — o cliente vai
/// validar/ajustar estes campos (ver ARCHITECTURE.md, ADR-010).
/// </summary>
public class RegrasMissao
{
    public int Id { get; set; }

    public required string Chave { get; init; } = "default";

    /// <summary>Nº máximo de linhas (artigos a picar) por missão.</summary>
    public int MaxLinhasPorMissao { get; set; } = 20;

    /// <summary>Nº máximo de plataformas/totes de destino distintas por missão.</summary>
    public int MaxPlataformasPorMissao { get; set; } = 4;

    /// <summary>Critério para agrupar Ordens de Preparação na mesma missão.</summary>
    public CriterioAgrupamento CriterioAgrupamento { get; set; } = CriterioAgrupamento.Zona;

    /// <summary>Critério para ordenar as linhas dentro de uma missão.</summary>
    public CriterioOrdenacao CriterioOrdenacao { get; set; } = CriterioOrdenacao.Localizacao;

    public DateTime AtualizadoEm { get; set; } = DateTime.UtcNow;
}

public enum CriterioAgrupamento
{
    Zona,
    Encomenda,
    Nenhum,
}

public enum CriterioOrdenacao
{
    Localizacao,
    Prioridade,
}
