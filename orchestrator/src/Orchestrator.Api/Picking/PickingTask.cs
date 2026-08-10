namespace Orchestrator.Api.Picking;

public enum PickingTaskStatus
{
    Pendente,
    EmProgresso,
    Concluida
}

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
