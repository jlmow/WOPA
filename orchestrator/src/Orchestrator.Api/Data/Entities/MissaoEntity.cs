namespace Orchestrator.Api.Data.Entities;

/// <summary>
/// Tabela picking.MISSAO — nome exato pedido pelo cliente. Generalizada
/// (ADR-015) para os seis centros de trabalho do documento de
/// requisitos v0.4 (secção 4.5) e para a máquina de estados de A.13:
/// Criada -&gt; Atribuida -&gt; EmExecucao -&gt; (Pausada &lt;-&gt; EmExecucao) -&gt;
/// Concluida | FechadaIncompleta.
/// </summary>
public class MissaoEntity
{
    public string Id { get; set; } = null!;
    public string Codigo { get; set; } = null!;
    public string? ZonaId { get; set; }
    public string? UtilizadorId { get; set; }
    public string? TerminalId { get; set; }
    public string Estado { get; set; } = "Criada";
    public DateTime CriadaEm { get; set; } = DateTime.UtcNow;
    public DateTime? ConcluidaEm { get; set; }

    /// <summary>Despacho com data (ADR-027) — só preenchido quando "Planeada" para um dia futuro.</summary>
    public DateOnly? DataPlaneada { get; set; }
    public string? CelulaId { get; set; }

    /// <summary>Gate de montagem (ADR-029) — true depois de montar/confirmar a plataforma desta missão.</summary>
    public bool PlataformaConfirmada { get; set; }
    public DateTime? PlataformaConfirmadaEm { get; set; }

    /// <summary>Picking | Packing | Transporte | Abastecimento | Reposicao | P0.</summary>
    public string CentroTrabalho { get; set; } = "Picking";
    public string? PlataformaId { get; set; }
    /// <summary>Rutura | FimTurno | MudancaPrioridade | Avaria (A.13).</summary>
    public string? MotivoPausa { get; set; }
    public DateTime? AtribuidaEm { get; set; }
    public DateTime? IniciadaEm { get; set; }
    public DateTime? PausadaEm { get; set; }
    public DateTime? RetomadaEm { get; set; }

    public List<MissaoLinhaEntity> Linhas { get; set; } = new();
}
