using System.Collections.Concurrent;

namespace Orchestrator.Api.Picking;

/// <summary>
/// Repositório em memória para a PoC. Numa fase seguinte é substituído por
/// acesso ao schema "picking" da base de dados WOPA (SQL Server).
/// </summary>
public class PickingStore
{
    private readonly ConcurrentDictionary<string, PickingTask> _tasks = new();

    public PickingStore()
    {
        Seed();
    }

    public IEnumerable<PickingTask> GetAll() =>
        _tasks.Values.OrderBy(t => t.Localizacao);

    public PickingTask? Get(string id) =>
        _tasks.GetValueOrDefault(id);

    public void Reset() => Seed();

    private void Seed()
    {
        _tasks.Clear();
        foreach (var task in new[]
        {
            new PickingTask
            {
                Id = "task-1",
                Sku = "SKU-1001",
                Descricao = "Parafuso M6x20 (caixa 100un)",
                CodigoBarras = "5601234567890",
                Localizacao = "A-01-03",
                QuantidadeAlvo = 3
            },
            new PickingTask
            {
                Id = "task-2",
                Sku = "SKU-2044",
                Descricao = "Luvas de proteção tamanho L",
                CodigoBarras = "5601234500021",
                Localizacao = "A-02-11",
                QuantidadeAlvo = 2
            },
            new PickingTask
            {
                Id = "task-3",
                Sku = "SKU-3390",
                Descricao = "Fita adesiva 48mm",
                CodigoBarras = "5601234511119",
                Localizacao = "B-04-02",
                QuantidadeAlvo = 5
            }
        })
        {
            _tasks[task.Id] = task;
        }
    }
}
