namespace Orchestrator.Api.Data.Entities;

/// <summary>
/// Tabela orchestrator.CM. Tipo é uma coluna calculada/persistida na BD
/// (CM_ID &lt; 500 = Entrada, &gt; 500 = Saida) — só de leitura a partir daqui.
/// </summary>
public class CodigoMovimentoEntity
{
    public int Id { get; set; }
    public string Descricao { get; set; } = null!;
    public string Tipo { get; set; } = null!;
}
