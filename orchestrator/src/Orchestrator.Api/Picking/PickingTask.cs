namespace Orchestrator.Api.Picking;

public enum PickingTaskStatus
{
    Pendente,
    EmProgresso,
    Concluida
}

/// <summary>
/// DTO da API pública — não é a entidade da base de dados (essa é
/// Data.Entities.MissaoLinhaEntity). Mantém o formato simples que o pda já
/// consome (Localizacao/Plataforma como texto) mesmo com o schema
/// normalizado por trás — ver ARCHITECTURE.md ADR-012 ("Opção A").
/// </summary>
public class PickingTask
{
    public required string Id { get; init; }
    public required string Sku { get; init; }
    public required string Descricao { get; init; }
    public required string CodigoBarras { get; init; }
    public required string Localizacao { get; init; }
    public required string Plataforma { get; init; }
    public required int QuantidadeAlvo { get; init; }
    public int QuantidadeLida { get; set; }
    public PickingTaskStatus Estado { get; set; } = PickingTaskStatus.Pendente;
}
