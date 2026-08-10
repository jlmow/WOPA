# Deployment do orchestrator no IIS

Este guia cobre o `orchestrator` (a API). Os frontends (`pda`, `controller`)
são só ficheiros estáticos — a secção 4 explica como os publicar a seguir
ao mesmo padrão.

Confirmei aqui que `dotnet publish` já gera o `web.config` correto para
IIS automaticamente (hosting in-process, sem precisar de tocar no
projeto) — não há nada a ajustar no código para isto funcionar.

## 0. Caminho automático: `deploy/install-wopa.ps1`

Se preferires não seguir os passos manuais abaixo, há um script
PowerShell que faz tudo — pré-requisitos, base de dados, publicar
`orchestrator`, compilar `pda`/`controller`, e configurar os três
sites no IIS:

```powershell
# copia o repositório para o servidor (ex. C:\wopa\install), depois:
cd C:\wopa\install\deploy
.\install-wopa.ps1 -SqlServer "WOPASRV\wopa" -HostName "172.16.4.15" -SeedRealistic
```

Corre `Get-Help .\install-wopa.ps1 -Full` para todos os parâmetros
(portas, caminhos, etc.). **Importante:** este script foi escrito e
revisto com cuidado, mas nunca correu num Windows Server real — o
ambiente onde foi escrito não tem acesso a um. Corre-o numa máquina de
teste primeiro se puderes, e avisa-me de qualquer erro para eu
corrigir. As secções 1–6 abaixo continuam válidas como referência do
que o script faz (e para quando quiseres fazer só uma parte à mão).

## 1. Pré-requisitos no servidor Windows

1. **IIS** instalado, com o módulo **URL Rewrite** (necessário para o
   SPA fallback do `pda`/`controller` — ver secção 4).
2. **.NET 8 Hosting Bundle** — não é só o SDK, é especificamente o
   *ASP.NET Core Hosting Bundle* (instala o módulo `AspNetCoreModuleV2`
   que o IIS usa para correr a app):
   https://dotnet.microsoft.com/download/dotnet/8.0 → secção "Hosting
   Bundle". Depois de instalar, reiniciar o IIS (`iisreset`).
3. Confirmar: no IIS Manager, o site raiz do servidor mostra o módulo
   "ASP.NET Core Module V2" nos módulos instalados.

## 2. Publicar o orchestrator

A partir de `orchestrator/src/Orchestrator.Api`:

```powershell
dotnet publish -c Release -o C:\inetpub\wopa\orchestrator
```

Isto gera os binários + `web.config` prontos para IIS na pasta de
destino. Repete este comando sempre que houver uma versão nova — não
apagues a pasta `logs` se já existir (ver secção 5).

## 2.1 Criar a base de dados (antes de tudo o resto)

A partir de qualquer máquina com acesso à rede do servidor SQL Server
(o próprio servidor, ou uma máquina com `sqlcmd`/SSMS instalado e VPN
para essa rede — **não é possível a partir deste ambiente de
desenvolvimento**, que corre isolado numa sandbox sem rota até à rede
do cliente):

```powershell
sqlcmd -S <servidor>\<instância> -U sa -P "<password>" -C -i database\schema.sql
```

Substitui `<servidor>\<instância>` e `<password>` pelos dados reais do
teu SQL Server. O script:

- Cria a base de dados `WOPA` se não existir (`CREATE DATABASE`).
- Cria todas as tabelas, guardadas por `IF NOT EXISTS` — seguro para
  correr mais que uma vez.
- Insere dados de exemplo (seed) para a PoC ter algo real para
  trabalhar assim que a base de dados nasce — zonas, um terminal, um
  operador de exemplo (número `42`, PIN `1234`), uma Ordem de
  Preparação/Plataforma/Missão de exemplo.

Confirma no fim que apareceu `Base de dados WOPA pronta.` na consola.
Se a ligação ao SQL Server exigir `TrustServerCertificate` ou outra
opção de encriptação diferente da tua rede, ajusta os flags do
`sqlcmd` (`-C` já assume "confiar no certificado do servidor", comum
em redes internas sem certificado válido).

## 3. Criar o site no IIS

1. **Application Pools** → criar um novo, ex. `WOPA-Orchestrator`.
   - **.NET CLR version: No Managed Code** (o ASP.NET Core corre fora
     do CLR clássico do IIS; isto é obrigatório, não opcional).
   - Start mode: `AlwaysRunning` (evita o "cold start" na primeira
     chamada depois do IIS reciclar o pool).
2. **Sites** → **Add Website**:
   - Physical path: `C:\inetpub\wopa\orchestrator`
   - Application pool: `WOPA-Orchestrator`
   - Binding: porta interna à tua escolha (ex. `8080`), ou um binding
     dedicado se o orchestrator vai ficar num domínio/subdomínio
     próprio (ex. `api.wopa.local`).
3. Testar: `http://localhost:8080/health` deve devolver `{"status":"ok"}`.
   Se der erro 502.5, confirma o Hosting Bundle (passo 1.2) e consulta
   os logs (secção 5).

## 4. Configuração para produção

- **CORS**: o `Program.cs` hoje só permite as origens de
  desenvolvimento (`localhost:5173`/`5174`, os dev servers do Vite).
  Em produção, `orchestrator`, `pda` e `controller` devem ficar atrás
  do **mesmo domínio/IIS** (a arquitetura conta com isto — ver
  ARCHITECTURE.md secção 1) e a política de CORS deixa de ser
  necessária; se ainda assim ficarem em domínios/portas diferentes,
  ajusta `DevClientsPolicy` no `Program.cs` para os domínios reais.
- **Base de dados**: corre `database/schema.sql` primeiro (ver secção
  2.1). Depois, o `orchestrator` precisa da connection string real —
  cria `appsettings.Production.json` ao lado de `appsettings.json`
  com:
  ```json
  { "ConnectionStrings": { "Wopa": "Server=<servidor>\\<instância>;Database=WOPA;User Id=sa;Password=<password>;TrustServerCertificate=True;" } }
  ```
  Se o servidor SQL não tiver um certificado TLS válido (comum em
  redes internas), mantém `TrustServerCertificate=True` (equivalente
  ao "Trust Server Certificate" do SSMS) ou usa `Encrypt=False` se a
  rede não tiver encriptação nenhuma configurada — replica aqui o
  mesmo que já usas para ligar via SSMS.
  Preferível a `appsettings.Production.json`: define a variável de
  ambiente `ConnectionStrings__Wopa` no Application Pool do IIS (mais
  seguro do que deixar a password em ficheiro, e evita que a password
  fique commitada por engano no repositório). **Nunca uses a
  connection string de `appsettings.Development.json`** — essa aponta
  para um contentor Docker local usado só para testar isto em
  desenvolvimento, não é o servidor do cliente.
- **Dados mestre de artigo**: o `orchestrator` tem
  `POST /api/artigos` (upsert em lote) para carregar o catálogo real
  (RF-ENT-03) — o seed do `schema.sql` só tem 3 artigos de exemplo. A
  integração real com o PHC para manter isto atualizado ainda está por
  desenhar (ver ARCHITECTURE.md secção 8); entretanto pode ser
  populado manualmente com um script que exporte do PHC e chame este
  endpoint.
- **HTTPS**: adiciona um binding HTTPS ao site com um certificado
  válido para a rede do cliente; hoje a app não força HTTPS (é uma
  decisão deliberada da PoC, ver `Program.cs` — sem
  `UseHttpsRedirection`) porque tudo corre atrás do IIS on-premise.

## 5. Logs

O `web.config` gerado tem `stdoutLogEnabled="false"` por omissão. Para
depurar um deployment que não arranca:

```xml
<aspNetCore processPath="dotnet" arguments=".\Orchestrator.Api.dll"
            stdoutLogEnabled="true" stdoutLogFile=".\logs\stdout" .../>
```

Cria a pasta `logs` na raiz do site (o IIS não a cria sozinho) e volta
a tentar. Desliga outra vez depois de resolver — ficheiros de log sem
rotação enchem disco.

## 6. Publicar `pda` e `controller` (ficheiros estáticos)

Ambos são builds Vite normais:

```powershell
cd pda        # ou controller
npm install
npm run build     # gera dist/
```

Copia o conteúdo de `dist/` para uma pasta servida por um site IIS
próprio (ex. `C:\inetpub\wopa\pda`), com **Physical Path Credentials**
normais (site estático, não precisa de application pool "No Managed
Code" — pode até ficar no mesmo pool default do IIS).

Antes do build, aponta `VITE_ORCHESTRATOR_URL` para o endereço real do
orchestrator neste servidor (não `localhost:5080`, que só funciona em
desenvolvimento) — cria um `.env.production` em `pda/` e `controller/`:

```
VITE_ORCHESTRATOR_URL=http://api.wopa.local
```

**Importante:** tanto `pda/public/web.config` como
`controller/public/web.config` já têm a regra de SPA fallback (serve
sempre `index.html` em rotas desconhecidas, para `/login`,
`/ordens-preparacao`, etc. funcionarem em refresh) — copiados
automaticamente para `dist/` no build de cada um, não precisas de
criar nada.

## 7. Caminho rápido para uma prova de conceito, sem IIS

Se quiseres testar o `pda` num PDA Android já, sem esperar pelo
deployment completo em IIS:

```powershell
# numa máquina Windows na mesma rede Wi-Fi do armazém
cd orchestrator\src\Orchestrator.Api
dotnet run --urls http://0.0.0.0:5080

# noutro terminal
cd pda
npm run build
npx serve dist -l 5173 --host 0.0.0.0
```

Depois, no PDA, aponta o Chrome para `http://<IP da máquina>:5173` —
ver `pda/INSTALAR-NO-PDA.md` para os passos de instalação como app no
dispositivo. Isto evita configurar IIS já, só para validar que o
fluxo funciona ponta a ponta num dispositivo real.
