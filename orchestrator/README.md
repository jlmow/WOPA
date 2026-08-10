# WOPA orchestrator

API central ("Cérebro") do WOPA — ver `ARCHITECTURE.md` na raiz do
repositório para o desenho completo.

## Correr localmente

Precisa de um SQL Server acessível (ver `database/schema.sql` para
criar a base de dados `WOPA`) e da connection string em
`appsettings.Development.json` (chave `ConnectionStrings:Wopa`) — não
corre mais em memória.

```bash
cd src/Orchestrator.Api
dotnet run --urls http://localhost:5080
```

Para publicar em IIS, ver `DEPLOY.md`.
