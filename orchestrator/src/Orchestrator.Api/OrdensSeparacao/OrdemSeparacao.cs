namespace Orchestrator.Api.OrdensSeparacao;

/// <summary>
/// Uma linha de PS — um artigo e a quantidade a separar. AlveoloCodigo
/// é opcional porque nem toda origem tem necessariamente essa
/// informação disponível. Reaproveitado como o formato de linha dentro
/// de um PS recebido numa Ordem de Preparação (ver
/// OrdensPreparacao.PsRecebido, ADR-017).
/// </summary>
public record OrdemSeparacaoLinha(string Sku, int Quantidade, string? AlveoloCodigo);
