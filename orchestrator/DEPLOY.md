# Deployment do orchestrator no IIS

Este guia cobre o `orchestrator` (a API). Os frontends (`pda`, `controller`)
são só ficheiros estáticos — a secção 4 explica como os publicar a seguir
ao mesmo padrão.

Confirmei aqui que `dotnet publish` já gera o `web.config` correto para
IIS automaticamente (hosting in-process, sem precisar de tocar no
projeto) — não há nada a ajustar no código para isto funcionar.

**Discos:** os três sites do WOPA (`orchestrator`, `pda`, `controller`)
vivem em `E:\wopa\...` — o disco reservado à API neste servidor.
Ferramentas e pré-requisitos (SDKs, Hosting Bundle, o clone/cópia do
repositório para build) ficam em `C:\` como habitual. Todos os
caminhos deste guia e do `install-wopa.ps1` já refletem isto.

## 0. Caminho automático: `deploy/install-wopa.ps1`

Se preferires não seguir os passos manuais abaixo, há um script
PowerShell que faz tudo — pré-requisitos, base de dados, publicar
`orchestrator`, compilar `pda`/`controller`, e configurar os três
sites no IIS:

```powershell
# 1. Abre o PowerShell como Administrador (Menu Iniciar -> PowerShell
#    -> botao direito -> "Executar como Administrador"). NAO uses a
#    Command Prompt (cmd.exe) nem duplo-clique no ficheiro.
# 2. Copia o repositorio para o servidor, em qualquer disco/pasta
#    (o script deteta sozinho onde esta -- nao precisas de o copiar
#    para um caminho especifico). Depois:
cd E:\wopa\install\deploy      # ajusta ao caminho onde copiaste
Unblock-File .\install-wopa.ps1
.\install-wopa.ps1 -SqlServer "WOPASRV\wopa" -HostName "172.16.4.15" -SeedRealistic
```

Corre `Get-Help .\install-wopa.ps1 -Full` para todos os parâmetros
(portas, caminhos, etc.). **Importante:** este script foi escrito e
revisto com cuidado, mas nunca correu num Windows Server real — o
ambiente onde foi escrito não tem acesso a um. Corre-o numa máquina de
teste primeiro se puderes, e avisa-me de qualquer erro para eu
corrigir. As secções 1–6 abaixo continuam válidas como referência do
que o script faz (e para quando quiseres fazer só uma parte à mão).

## 0.1 Deploy direto do GitHub (`.github/workflows/deploy.yml`)

Depois da primeira instalação (secção 0) estar feita, dá para acionar
deploys seguintes diretamente a partir do GitHub, sem teres de copiar
ficheiros à mão outra vez — através de um **runner self-hosted**
instalado no próprio servidor. O servidor não tem acesso de entrada
(inbound) da internet, por isso não é um runner normal do GitHub na
cloud — é um processo que corre no servidor e liga-se **para fora**
ao GitHub à procura de trabalho (a mesma direção de ligação que já
usas para instalar pacotes, sem abrir nada na firewall).

**1. Instalar o runner no servidor** (uma vez só): no GitHub, vai a
`Settings` → `Actions` → `Runners` → `New self-hosted runner`, escolhe
Windows, e segue os comandos que o GitHub te mostra ali — são
específicos da tua conta/repositório (têm um token de registo válido
por pouco tempo, por isso não os posso escrever aqui antecipadamente).
No fim, instala-o como serviço Windows (o próprio assistente do GitHub
pergunta isto) para ficar sempre a correr, mesmo depois de reiniciares
o servidor.

**2. Configurar os secrets do repositório**: `Settings` → `Secrets and
variables` → `Actions` → `New repository secret`, um por cada:

| Secret | Valor |
|---|---|
| `WOPA_SQL_SERVER` | ex. `WOPASRV\wopa` |
| `WOPA_SQL_USER` | ex. `sa` |
| `WOPA_SQL_PASSWORD` | a password do SQL Server |
| `WOPA_HOST` | ex. `172.16.4.15` — o IP/nome pelo qual os PDAs/postos acedem ao servidor |

Nunca ficam no código nem nos logs do workflow — o GitHub oculta
automaticamente qualquer valor de um secret que apareça no output.

**3. Disparar um deploy**: separador `Actions` do repositório →
"Deploy WOPA para o IIS" → `Run workflow`. Por omissão só publica
`orchestrator`/`pda`/`controller` e reinicia os sites (**não** toca na
base de dados — `-SkipDatabase`); marca a opção "Carregar dados
quase-reais" só se quiseres repetir esse carregamento a sério (não é
para deploys de rotina).

O workflow está deliberadamente configurado para correr só quando
pedes (`workflow_dispatch`), não em cada `push` — o `orchestrator`
fala com a base de dados real do cliente, por isso um deploy
automático a cada commit não é o comportamento certo por omissão.
Se, mais à frente, quiseres deploy automático a cada push para `main`,
é uma alteração pequena ao ficheiro do workflow (adicionar um gatilho
`push`) — pede-me quando fizer sentido.

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

A partir de `orchestrator/src/Orchestrator.Api`. **Publica para o disco
reservado à API (`E:\` neste servidor) — os sites do WOPA vivem em
`E:\`, só as ferramentas/pré-requisitos (SDKs, Hosting Bundle) ficam
em `C:\`:**

```powershell
dotnet publish -c Release -o E:\wopa\orchestrator
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
   - Physical path: `E:\wopa\orchestrator`
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
próprio (ex. `E:\wopa\pda` — disco reservado à API, mesma regra da
secção 2), com **Physical Path Credentials** normais (site estático,
não precisa de application pool "No Managed Code" — pode até ficar no
mesmo pool default do IIS).

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
