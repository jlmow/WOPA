using Microsoft.EntityFrameworkCore;
using Orchestrator.Api.Config;
using Orchestrator.Api.Data.Entities;

namespace Orchestrator.Api.Data;

/// <summary>
/// Mapeia diretamente para as tabelas criadas por database/schema.sql
/// (esse script é que cria o schema — este DbContext não usa migrations,
/// é "database first" por desenho).
/// </summary>
public class WopaDbContext(DbContextOptions<WopaDbContext> options) : DbContext(options)
{
    public DbSet<ZonaEntity> Zonas => Set<ZonaEntity>();
    public DbSet<ModuloEntity> Modulos => Set<ModuloEntity>();
    public DbSet<TerminalEntity> Terminais => Set<TerminalEntity>();
    public DbSet<UtilizadorEntity> Utilizadores => Set<UtilizadorEntity>();
    public DbSet<AlveoloEntity> Alveolos => Set<AlveoloEntity>();
    public DbSet<CestoEntity> Cestos => Set<CestoEntity>();
    public DbSet<TipoPlataformaEntity> TiposPlataforma => Set<TipoPlataformaEntity>();
    public DbSet<CodigoMovimentoEntity> CodigosMovimento => Set<CodigoMovimentoEntity>();
    public DbSet<RegrasMissao> RegrasMissao => Set<RegrasMissao>();
    public DbSet<OrdemSeparacaoEntity> OrdensSeparacao => Set<OrdemSeparacaoEntity>();
    public DbSet<OrdemSeparacaoLinhaEntity> OrdensSeparacaoLinhas => Set<OrdemSeparacaoLinhaEntity>();
    public DbSet<MissaoEntity> Missoes => Set<MissaoEntity>();
    public DbSet<MissaoLinhaEntity> MissaoLinhas => Set<MissaoLinhaEntity>();
    public DbSet<OperacaoProcessadaEntity> OperacoesProcessadas => Set<OperacaoProcessadaEntity>();
    public DbSet<ArtigoEntity> Artigos => Set<ArtigoEntity>();
    public DbSet<OrdemPreparacaoEntity> OrdensPreparacao => Set<OrdemPreparacaoEntity>();
    public DbSet<PlataformaEntity> Plataformas => Set<PlataformaEntity>();
    public DbSet<EstoqueAlveoloEntity> Estoque => Set<EstoqueAlveoloEntity>();
    public DbSet<MovimentoStockEntity> MovimentosStock => Set<MovimentoStockEntity>();
    public DbSet<CelulaEntity> Celulas => Set<CelulaEntity>();
    public DbSet<PlataformaCestoEntity> PlataformaCestos => Set<PlataformaCestoEntity>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<ZonaEntity>(e =>
        {
            e.ToTable("Zonas");
            e.HasKey(x => x.Id);
        });

        modelBuilder.Entity<ModuloEntity>(e =>
        {
            e.ToTable("Modulos");
            e.HasKey(x => x.Slug);
        });

        modelBuilder.Entity<TerminalEntity>(e =>
        {
            e.ToTable("TER");
            e.HasKey(x => x.Id);
        });

        modelBuilder.Entity<UtilizadorEntity>(e =>
        {
            e.ToTable("US");
            e.HasKey(x => x.Id);
        });

        modelBuilder.Entity<AlveoloEntity>(e =>
        {
            e.ToTable("ALV");
            e.HasKey(x => x.Id);
            e.HasOne(x => x.Zona).WithMany().HasForeignKey(x => x.ZonaId);
        });

        modelBuilder.Entity<CestoEntity>(e =>
        {
            e.ToTable("CESTOS");
            e.HasKey(x => x.Id);
        });

        modelBuilder.Entity<TipoPlataformaEntity>(e =>
        {
            e.ToTable("TiposPlataforma");
            e.HasKey(x => x.Codigo);
        });

        modelBuilder.Entity<CodigoMovimentoEntity>(e =>
        {
            e.ToTable("CM");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).ValueGeneratedNever();
            // Tipo é coluna calculada/persistida na BD — só de leitura por aqui.
            e.Property(x => x.Tipo).ValueGeneratedOnAddOrUpdate();
        });

        modelBuilder.Entity<RegrasMissao>(e =>
        {
            e.ToTable("RegrasMissao");
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.Chave).IsUnique();
            e.Property(x => x.CriterioAgrupamento).HasConversion<string>().HasMaxLength(30);
            e.Property(x => x.CriterioOrdenacao).HasConversion<string>().HasMaxLength(30);
        });

        modelBuilder.Entity<OrdemSeparacaoEntity>(e =>
        {
            e.ToTable("OrdensSeparacao");
            e.HasKey(x => x.Id);
            e.HasMany(x => x.Linhas).WithOne().HasForeignKey(x => x.OrdemSeparacaoId);
            e.HasOne<OrdemPreparacaoEntity>().WithMany(x => x.Ps).HasForeignKey(x => x.OrdemPreparacaoId);
        });

        modelBuilder.Entity<OrdemSeparacaoLinhaEntity>(e =>
        {
            e.ToTable("OrdensSeparacaoLinhas");
            e.HasKey(x => x.Id);
            e.HasOne(x => x.Alveolo).WithMany().HasForeignKey(x => x.AlveoloId);
            // Sem isto, o EF não sabe que PlataformaId depende de
            // Plataformas.Id e pode tentar o UPDATE antes do INSERT da
            // plataforma nova na mesma transação (bug real encontrado ao
            // testar a tipificação a sério contra SQL Server).
            e.HasOne<PlataformaEntity>().WithMany().HasForeignKey(x => x.PlataformaId);
        });

        modelBuilder.Entity<ArtigoEntity>(e =>
        {
            e.ToTable("Artigos");
            e.HasKey(x => x.Sku);
        });

        modelBuilder.Entity<OrdemPreparacaoEntity>(e =>
        {
            e.ToTable("OrdensPreparacao");
            e.HasKey(x => x.Id);
        });

        modelBuilder.Entity<PlataformaEntity>(e =>
        {
            e.ToTable("Plataformas");
            e.HasKey(x => x.Id);
            e.HasOne(x => x.TipoPlataforma).WithMany().HasForeignKey(x => x.TipoPlataformaCodigo);
            e.HasOne<OrdemPreparacaoEntity>().WithMany(x => x.Plataformas).HasForeignKey(x => x.OrdemPreparacaoId);
        });

        modelBuilder.Entity<MissaoEntity>(e =>
        {
            e.ToTable("MISSAO");
            e.HasKey(x => x.Id);
            e.HasMany(x => x.Linhas).WithOne().HasForeignKey(x => x.MissaoId);
            e.HasOne<PlataformaEntity>().WithMany().HasForeignKey(x => x.PlataformaId);
            e.HasOne<CelulaEntity>().WithMany().HasForeignKey(x => x.CelulaId);
        });

        modelBuilder.Entity<MissaoLinhaEntity>(e =>
        {
            e.ToTable("MissaoLinhas");
            e.HasKey(x => x.Id);
            e.HasOne(x => x.Alveolo).WithMany().HasForeignKey(x => x.AlveoloId);
            e.Property(x => x.Estado).HasConversion<string>().HasMaxLength(20);
        });

        modelBuilder.Entity<OperacaoProcessadaEntity>(e =>
        {
            e.ToTable("OperacoesProcessadas");
            e.HasKey(x => x.OperacaoId);
        });

        modelBuilder.Entity<EstoqueAlveoloEntity>(e =>
        {
            e.ToTable("SA");
            e.HasKey(x => new { x.Sku, x.AlveoloId });
            e.HasOne(x => x.Alveolo).WithMany().HasForeignKey(x => x.AlveoloId);
        });

        modelBuilder.Entity<MovimentoStockEntity>(e =>
        {
            e.ToTable("SL");
            e.HasKey(x => x.Id);
        });

        modelBuilder.Entity<CelulaEntity>(e =>
        {
            e.ToTable("Celulas");
            e.HasKey(x => x.Id);
        });

        modelBuilder.Entity<PlataformaCestoEntity>(e =>
        {
            e.ToTable("PlataformaCestos");
            e.HasKey(x => x.Id);
            e.HasOne<PlataformaEntity>().WithMany().HasForeignKey(x => x.PlataformaId);
        });
    }
}
