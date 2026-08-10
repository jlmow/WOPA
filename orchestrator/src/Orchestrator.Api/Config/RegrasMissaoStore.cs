namespace Orchestrator.Api.Config;

/// <summary>
/// Repositório em memória para a PoC — na versão final isto lê/escreve na
/// tabela orchestrator.RegrasMissao (ver database/schema.sql) e é editável
/// a partir do core-config.
/// </summary>
public class RegrasMissaoStore
{
    private RegrasMissao _atual = new() { Chave = "default" };
    private readonly object _lock = new();

    public RegrasMissao Obter()
    {
        lock (_lock)
        {
            return _atual;
        }
    }

    public RegrasMissao Atualizar(RegrasMissao novas)
    {
        lock (_lock)
        {
            novas.AtualizadoEm = DateTime.UtcNow;
            _atual = novas;
            return _atual;
        }
    }
}
