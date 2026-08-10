using System.Collections.Concurrent;

namespace Orchestrator.Api.OrdensSeparacao;

/// <summary>
/// Repositório em memória para a PoC. Na versão final corresponde às
/// tabelas orchestrator.OrdensSeparacao / OrdensSeparacaoLinhas (ver
/// database/schema.sql).
/// </summary>
public class OrdensSeparacaoStore
{
    private readonly ConcurrentDictionary<string, OrdemSeparacao> _ordens = new();

    public OrdemSeparacao Adicionar(NovaOrdemSeparacaoRequest pedido)
    {
        var ordem = new OrdemSeparacao
        {
            Id = Guid.NewGuid().ToString("n"),
            NumeroDocumento = pedido.NumeroDocumento,
            Origem = pedido.Origem,
            Linhas = pedido.Linhas,
        };
        _ordens[ordem.Id] = ordem;
        return ordem;
    }

    public IEnumerable<OrdemSeparacao> GetAll() =>
        _ordens.Values.OrderByDescending(o => o.RecebidaEm);

    public OrdemSeparacao? Get(string id) =>
        _ordens.GetValueOrDefault(id);
}
