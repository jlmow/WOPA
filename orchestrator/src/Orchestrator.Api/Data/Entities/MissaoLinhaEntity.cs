using Orchestrator.Api.Picking;

namespace Orchestrator.Api.Data.Entities;

/// <summary>
/// Tabela picking.MissaoLinhas — uma linha por artigo a picar. Guarda
/// AlveoloId/TipoPlataformaCodigo/CestoId (normalizado); a API pública
/// continua a expor Localizacao/Plataforma como texto simples (Opção A) —
/// ver PickingEndpoints e ARCHITECTURE.md ADR-012.
/// </summary>
public class MissaoLinhaEntity
{
    public string Id { get; set; } = null!;
    public string MissaoId { get; set; } = null!;
    public string Sku { get; set; } = null!;
    public string Descricao { get; set; } = null!;
    public string CodigoBarras { get; set; } = null!;
    /// <summary>NULL para zonas sem detalhe de alvéolo (ex.: Armazém Automático).</summary>
    public string? AlveoloId { get; set; }
    public string Plataforma { get; set; } = null!;
    public string TipoPlataformaCodigo { get; set; } = null!;
    public string? CestoId { get; set; }
    public int CestosNecessarios { get; set; }
    public int QuantidadeAlvo { get; set; }
    public int QuantidadeLida { get; set; }
    public PickingTaskStatus Estado { get; set; } = PickingTaskStatus.Pendente;

    public AlveoloEntity? Alveolo { get; set; }
}
