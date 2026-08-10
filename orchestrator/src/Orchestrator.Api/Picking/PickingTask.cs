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

    /// <summary>
    /// Cópia imutável do estado atual — usada para guardar o resultado de uma
    /// operação idempotente sem ficar agarrada à instância mutável (que pode
    /// ser alterada por operações seguintes).
    /// </summary>
    public PickingTask Clone() => new()
    {
        Id = Id,
        Sku = Sku,
        Descricao = Descricao,
        CodigoBarras = CodigoBarras,
        Localizacao = Localizacao,
        Plataforma = Plataforma,
        QuantidadeAlvo = QuantidadeAlvo,
        QuantidadeLida = QuantidadeLida,
        Estado = Estado,
    };
}
