<#
.SYNOPSIS
    Instala o WOPA (orchestrator + pda + controller) num servidor Windows
    com IIS, a partir de uma cópia do repositório já copiada para o
    servidor (ver -SourceRoot).

.DESCRIPTION
    Cobre o mesmo trabalho descrito em orchestrator/DEPLOY.md, mas de
    ponta a ponta: confirma pré-requisitos (tenta instalar os que
    faltarem), cria a base de dados WOPA, publica o orchestrator,
    compila o pda e o controller, e cria os sites/application pools no
    IIS. Idempotente onde é razoável (não recria o que já existe), para
    poderes correr outra vez em segurança depois de uma atualização.

    NÃO TESTADO NUM SERVIDOR WINDOWS REAL — foi escrito e revisto com
    cuidado (sintaxe e cmdlets do WebAdministration/IIS confirmados),
    mas nunca correu de facto num Windows Server, porque o ambiente
    onde foi escrito não tem acesso a um. Corre-o primeiro numa
    máquina de teste, ou lê-o com atenção antes de correr no servidor a
    sério — e diz-me qualquer erro que apareça, para eu corrigir.

    COMO CORRER (importante): abre o PowerShell como Administrador
    (Menu Iniciar → escreve "PowerShell" → botão direito → "Executar
    como Administrador") e corre o script a partir daí com `.\`. NÃO
    uses "Run with PowerShell" no menu de contexto do Explorer nem
    duplo-clique — essa janela fecha-se sozinha assim que o script
    acaba (ou falha), sem dar tempo a ler nada. Se copiaste o
    ficheiro de outra máquina (rede, USB, etc.), o Windows marca-o
    como "bloqueado" e o PowerShell recusa-se a correr — corre
    primeiro `Unblock-File .\install-wopa.ps1`. Se mesmo assim vires
    um erro sobre "execution policy", corre
    `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` nessa
    mesma janela antes de tentares outra vez (só afeta esta sessão).

.PARAMETER SourceRoot
    Onde copiaste o repositório (a pasta que tem orchestrator/, pda/,
    controller/). Por omissão, a pasta-mãe de onde este próprio script
    está a correr (ex.: se o script está em E:\wopa\install\deploy,
    assume E:\wopa\install) — normalmente não precisas de passar isto,
    seja qual for a drive/pasta para onde copiaste o projeto.

.PARAMETER InstallRoot
    Onde os SITES do WOPA ficam instalados (orchestrator publicado,
    pda/controller compilados — o que o IIS serve). Por omissão
    E:\wopa, o disco reservado no servidor para a API — nada dos
    pré-requisitos (IIS, Hosting Bundle, SDKs) vai para aqui, só o
    conteúdo dos três sites.

.PARAMETER SqlServer
    Instância do SQL Server, ex. "WOPASRV\wopa" ou "172.16.4.15\wopa".

.PARAMETER SqlUser
    Utilizador SQL (autenticação SQL). Por omissão "sa".

.PARAMETER SqlPassword
    Password do utilizador SQL. Pedida de forma segura se não for
    passada (recomendado — evita ficar em texto simples no histórico
    de comandos).

.PARAMETER HostName
    Nome/IP pelo qual OUTRAS máquinas (PDAs, postos do controller) vão
    aceder a este servidor. Por omissão "localhost" — muda para o IP
    real do servidor na rede do armazém, senão só funciona a partir do
    próprio servidor.

.PARAMETER OrchestratorPort / PdaPort / ControllerPort
    Portas dos três sites IIS. Por omissão 8080 / 8081 / 8082.

.PARAMETER SeedRealistic
    Também carrega database/seed-realistic.sql (dados quase-reais para
    demonstração — ver ARCHITECTURE.md ADR-019) depois do schema.sql.

.PARAMETER SkipPrereqInstall
    Não tenta instalar pré-requisitos em falta (Hosting Bundle, URL
    Rewrite, Node.js, .NET SDK) — só verifica e avisa. Usa isto se o
    servidor não tem acesso à internet, ou se preferes instalar isso
    manualmente primeiro.

.PARAMETER SkipDatabase
    Não corre schema.sql/seed-realistic.sql — usa isto nos deploys de
    rotina (ex. a partir do GitHub Actions) depois da base de dados já
    ter sido criada uma vez, para não tocar nela em cada deploy.

.PARAMETER CI
    Modo não interativo — para correr a partir de automação (ex.
    GitHub Actions self-hosted runner), onde não há ninguém para
    responder a prompts nem para premir ENTER no fim. Sem isto, o
    script para à espera de input e a automação fica pendurada para
    sempre. Se não passares -SqlPassword neste modo, falha logo com
    erro claro em vez de tentar perguntar.

.EXAMPLE
    .\install-wopa.ps1 -SqlServer "WOPASRV\wopa" -HostName "172.16.4.15" -SeedRealistic

.EXAMPLE
    # deploy de rotina, chamado pelo GitHub Actions (ver .github/workflows/deploy.yml)
    .\install-wopa.ps1 -SqlServer "WOPASRV\wopa" -HostName "172.16.4.15" -SqlPassword $env:SQL_PASSWORD -SkipPrereqInstall -SkipDatabase -CI
#>

[CmdletBinding()]
param(
    [string]$SourceRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$InstallRoot = "E:\wopa",
    [Parameter(Mandatory = $true)]
    [string]$SqlServer,
    [string]$SqlUser = "sa",
    [string]$SqlPassword,
    [string]$HostName = "localhost",
    [int]$OrchestratorPort = 8080,
    [int]$PdaPort = 8081,
    [int]$ControllerPort = 8082,
    [switch]$SeedRealistic,
    [switch]$SkipPrereqInstall,
    [switch]$SkipDatabase,
    [switch]$CI
)

$ErrorActionPreference = "Stop"

# Auto-deteta automação mesmo sem -CI explícito (GitHub Actions define
# sempre estas variáveis de ambiente no runner).
$isCiRun = $CI -or $env:GITHUB_ACTIONS -eq "true" -or $env:CI -eq "true"

function Wait-BeforeExit {
    if (-not $isCiRun) {
        Write-Host ""
        Read-Host "Prima ENTER para fechar"
    }
}

# Verificação manual (em vez de "#Requires -RunAsAdministrator") --
# assim, se não estiveres elevado, o script consegue mostrar uma
# mensagem clara e esperar por ENTER antes de fechar, em vez de a
# janela simplesmente desaparecer sem dares tempo a ler o erro.
$currentUser = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "Este script tem de correr como Administrador." -ForegroundColor Red
    Write-Host "Fecha esta janela, abre o PowerShell como Administrador" -ForegroundColor Yellow
    Write-Host "(Menu Iniciar -> 'PowerShell' -> botao direito -> 'Executar como Administrador')" -ForegroundColor Yellow
    Write-Host "e corre o script outra vez a partir dai." -ForegroundColor Yellow
    Wait-BeforeExit
    exit 1
}

# Tudo a partir daqui corre dentro de um try/catch/finally: se algo
# falhar a meio (mesmo lançado por um cmdlet nativo), a janela mostra
# o erro e espera por ENTER antes de fechar -- para quem correr isto
# com duplo-clique / "Run with PowerShell" (que fecha a janela sozinha
# assim que o processo termina) conseguir mesmo ler o que aconteceu.
try {

function Write-Step($msg) {
    Write-Host ""
    Write-Host "=== $msg ===" -ForegroundColor Cyan
}

function Write-Ok($msg) {
    Write-Host "  OK: $msg" -ForegroundColor Green
}

function Write-Warn2($msg) {
    Write-Host "  AVISO: $msg" -ForegroundColor Yellow
}

# -------------------------------------------------------------------
# 0. Validações iniciais
# -------------------------------------------------------------------

Write-Step "A validar parâmetros e pré-condições"

if (-not (Test-Path $SourceRoot)) {
    throw "SourceRoot '$SourceRoot' não existe. Copia o repositório para lá primeiro (ou passa -SourceRoot com o caminho certo)."
}
foreach ($proj in @("orchestrator", "pda", "controller")) {
    if (-not (Test-Path (Join-Path $SourceRoot $proj))) {
        throw "Não encontrei '$proj' dentro de '$SourceRoot' — confirma que copiaste a raiz do repositório completa."
    }
}

if (-not $SqlPassword) {
    if ($isCiRun) {
        throw "-SqlPassword não foi passado e isto está a correr em modo automático (-CI) -- não há ninguém para responder a um prompt. Passa a password (ex. a partir de um secret do GitHub Actions)."
    }
    $secure = Read-Host "Password do SQL Server (utilizador '$SqlUser')" -AsSecureString
    $SqlPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
}

# InstallRoot é onde os SITES ficam (o que o IIS serve) -- por pedido
# explícito, isto vai para o disco reservado à API (E:\ por omissão),
# não para C:. Falha cedo e com uma mensagem clara se a drive não
# existir, em vez de deixar o New-Item criar uma pasta nalgum sítio
# inesperado.
$installDrive = [System.IO.Path]::GetPathRoot($InstallRoot)
if (-not (Test-Path $installDrive)) {
    throw "A drive '$installDrive' (de -InstallRoot '$InstallRoot') não existe neste servidor. Confirma a letra da drive reservada à API, ou passa -InstallRoot com o caminho certo."
}
New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
Write-Ok "SourceRoot=$SourceRoot (build) InstallRoot=$InstallRoot (sites) SqlServer=$SqlServer HostName=$HostName"

# -------------------------------------------------------------------
# 1. Pré-requisitos
# -------------------------------------------------------------------

Write-Step "A verificar pré-requisitos"

function Test-Command($name) {
    return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

$needsIisReset = $false

# 1.1 IIS (função de servidor Web-Server)
$iisFeature = Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue
if ($iisFeature -and -not $iisFeature.Installed) {
    if ($SkipPrereqInstall) {
        Write-Warn2 "IIS não está instalado e -SkipPrereqInstall foi pedido — instala manualmente: Install-WindowsFeature Web-Server -IncludeManagementTools"
    }
    else {
        Write-Host "  A instalar a função IIS (Web-Server)..."
        Install-WindowsFeature -Name Web-Server -IncludeManagementTools | Out-Null
        $needsIisReset = $true
        Write-Ok "IIS instalado"
    }
}
else {
    Write-Ok "IIS já instalado"
}

# 1.2 .NET Hosting Bundle (módulo AspNetCoreModuleV2) -- verifica se o
# ficheiro do módulo existe; se não, tenta descarregar e instalar.
#
# NOTA: não tenho forma de confirmar a partir daqui (sandbox sem acesso
# à internet pública) que a URL abaixo ainda está válida no momento em
# que corres isto -- os instaladores da Microsoft mudam de URL a cada
# patch. Por isso este passo nunca pára o script (try/catch): se a
# descarga falhar, instala manualmente a partir da página estável
# https://dotnet.microsoft.com/download/dotnet/8.0 (secção "Hosting
# Bundle") e corre o script outra vez -- ele deteta que já está
# instalado e salta este passo.
$aspNetCoreModulePath = "$env:ProgramFiles\IIS\Asp.Net Core Module\V2\aspnetcorev2.dll"
if (-not (Test-Path $aspNetCoreModulePath)) {
    if ($SkipPrereqInstall) {
        Write-Warn2 "ASP.NET Core Hosting Bundle não encontrado. Instala manualmente: https://dotnet.microsoft.com/download/dotnet/8.0 (secção 'Hosting Bundle')."
    }
    else {
        Write-Host "  A tentar descarregar e instalar o ASP.NET Core 8 Hosting Bundle..."
        try {
            $bundleUrl = "https://dotnet.microsoft.com/download/dotnet/thank-you/runtime-aspnetcore-8.0.11-windows-hosting-bundle-installer"
            $bundlePath = Join-Path $env:TEMP "dotnet-hosting-8.0-win.exe"
            Invoke-WebRequest -Uri $bundleUrl -OutFile $bundlePath -UseBasicParsing -ErrorAction Stop
            Start-Process -FilePath $bundlePath -ArgumentList "/quiet", "/norestart" -Wait
            Remove-Item $bundlePath -ErrorAction SilentlyContinue
            $needsIisReset = $true
            Write-Ok "Hosting Bundle instalado"
        }
        catch {
            Write-Warn2 "Não consegui descarregar/instalar o Hosting Bundle automaticamente ($($_.Exception.Message)). Instala manualmente: https://dotnet.microsoft.com/download/dotnet/8.0 (secção 'Hosting Bundle'), depois corre este script outra vez."
        }
    }
}
else {
    Write-Ok "ASP.NET Core Hosting Bundle já instalado"
}

# 1.3 URL Rewrite (necessário para o SPA fallback do pda/controller) --
# mesma ressalva da URL que o passo anterior: se falhar, instala
# manualmente a partir de https://www.iis.net/downloads/microsoft/url-rewrite
$urlRewriteKey = "HKLM:\SOFTWARE\Microsoft\IIS Extensions\URL Rewrite"
if (-not (Test-Path $urlRewriteKey)) {
    if ($SkipPrereqInstall) {
        Write-Warn2 "Módulo URL Rewrite do IIS não encontrado. Instala manualmente: https://www.iis.net/downloads/microsoft/url-rewrite"
    }
    else {
        Write-Host "  A tentar descarregar e instalar o módulo URL Rewrite do IIS..."
        try {
            $rewriteUrl = "https://download.microsoft.com/download/1/2/8/128E2E22-C1B9-44A4-BE2A-5859ED1D4592/rewrite_amd64_en-US.msi"
            $rewritePath = Join-Path $env:TEMP "urlrewrite.msi"
            Invoke-WebRequest -Uri $rewriteUrl -OutFile $rewritePath -UseBasicParsing -ErrorAction Stop
            Start-Process -FilePath "msiexec.exe" -ArgumentList "/i", "`"$rewritePath`"", "/quiet", "/norestart" -Wait
            Remove-Item $rewritePath -ErrorAction SilentlyContinue
            $needsIisReset = $true
            Write-Ok "URL Rewrite instalado"
        }
        catch {
            Write-Warn2 "Não consegui descarregar/instalar o URL Rewrite automaticamente ($($_.Exception.Message)). Instala manualmente: https://www.iis.net/downloads/microsoft/url-rewrite, depois corre este script outra vez."
        }
    }
}
else {
    Write-Ok "URL Rewrite já instalado"
}

# 1.4 .NET SDK (necessário para "dotnet publish" -- o Hosting Bundle só
# traz o runtime, não o SDK)
if (-not (Test-Command "dotnet") -or -not (& dotnet --list-sdks 2>$null | Select-String "^8\.")) {
    if ($SkipPrereqInstall) {
        Write-Warn2 ".NET 8 SDK não encontrado. Instala manualmente: https://dotnet.microsoft.com/download/dotnet/8.0 (secção 'SDK')."
    }
    else {
        Write-Host "  A instalar o .NET 8 SDK via winget..."
        try {
            winget install --id Microsoft.DotNet.SDK.8 --silent --accept-package-agreements --accept-source-agreements
            Write-Ok ".NET 8 SDK instalado"
        }
        catch {
            Write-Warn2 "winget falhou a instalar o .NET SDK ($($_.Exception.Message)) -- instala manualmente."
        }
    }
}
else {
    Write-Ok ".NET 8 SDK já instalado"
}

# 1.5 Node.js (necessário para compilar pda e controller)
if (-not (Test-Command "npm")) {
    if ($SkipPrereqInstall) {
        Write-Warn2 "Node.js não encontrado. Instala manualmente: https://nodejs.org/ (versão LTS)."
    }
    else {
        Write-Host "  A instalar o Node.js LTS via winget..."
        try {
            winget install --id OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements
            Write-Ok "Node.js instalado"
        }
        catch {
            Write-Warn2 "winget falhou a instalar o Node.js ($($_.Exception.Message)) -- instala manualmente."
        }
    }
}
else {
    Write-Ok "Node.js já instalado"
}

# 1.6 sqlcmd (necessário para carregar o schema)
if (-not (Test-Command "sqlcmd")) {
    Write-Warn2 "sqlcmd não encontrado no PATH. Se o próximo passo (base de dados) falhar, instala o 'sqlcmd Utility': https://learn.microsoft.com/sql/tools/sqlcmd/sqlcmd-utility -- ou corre database/schema.sql manualmente via SSMS."
}
else {
    Write-Ok "sqlcmd disponível"
}

if ($needsIisReset) {
    Write-Host "  A reiniciar o IIS para aplicar os módulos instalados..."
    iisreset | Out-Null
}

# -------------------------------------------------------------------
# 2. Base de dados
# -------------------------------------------------------------------

if ($SkipDatabase) {
    Write-Step "A saltar a base de dados (-SkipDatabase)"
    Write-Ok "Assumido que schema.sql já foi aplicado antes -- típico num deploy de rotina"
}
else {
    Write-Step "A criar/atualizar a base de dados WOPA em $SqlServer"

    if (Test-Command "sqlcmd") {
        $schemaPath = Join-Path $SourceRoot "orchestrator\database\schema.sql"
        Write-Host "  A correr schema.sql..."
        & sqlcmd -S $SqlServer -U $SqlUser -P $SqlPassword -C -i $schemaPath
        if ($LASTEXITCODE -ne 0) { throw "schema.sql falhou (código $LASTEXITCODE) -- ver mensagens acima." }
        Write-Ok "schema.sql aplicado"

        if ($SeedRealistic) {
            $seedPath = Join-Path $SourceRoot "orchestrator\database\seed-realistic.sql"
            if (Test-Path $seedPath) {
                Write-Host "  A carregar dados quase-reais (seed-realistic.sql) -- pode demorar uns segundos..."
                & sqlcmd -S $SqlServer -U $SqlUser -P $SqlPassword -C -d WOPA -i $seedPath
                if ($LASTEXITCODE -ne 0) { throw "seed-realistic.sql falhou (código $LASTEXITCODE)." }
                Write-Ok "Dados quase-reais carregados"
            }
            else {
                Write-Warn2 "seed-realistic.sql não encontrado em '$seedPath' -- ignorado."
            }
        }
    }
    else {
        Write-Warn2 "sqlcmd indisponível -- salta a criação da base de dados. Corre orchestrator\database\schema.sql manualmente (SSMS ou sqlcmd) antes de usar o WOPA."
    }
}

$connectionString = "Server=$SqlServer;Database=WOPA;User Id=$SqlUser;Password=$SqlPassword;TrustServerCertificate=True;"

# -------------------------------------------------------------------
# 3. Publicar o orchestrator
# -------------------------------------------------------------------

Write-Step "A publicar o orchestrator"

$orchestratorSrc = Join-Path $SourceRoot "orchestrator\src\Orchestrator.Api"
$orchestratorOut = Join-Path $InstallRoot "orchestrator"

if (Test-Command "dotnet") {
    & dotnet publish $orchestratorSrc -c Release -o $orchestratorOut
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish falhou (código $LASTEXITCODE)." }
    Write-Ok "orchestrator publicado em $orchestratorOut"
}
else {
    throw ".NET SDK indisponível -- não é possível publicar o orchestrator. Instala o SDK e corre este script outra vez."
}

# appsettings.Production.json: connection string real + origens de CORS
# reais do pda/controller neste servidor (ver Program.cs -- lê
# Cors:AllowedOrigins da configuração).
$pdaUrl = "http://${HostName}:${PdaPort}"
$controllerUrl = "http://${HostName}:${ControllerPort}"
$appSettingsProd = @{
    ConnectionStrings = @{ Wopa = $connectionString }
    Cors              = @{ AllowedOrigins = @($pdaUrl, $controllerUrl) }
} | ConvertTo-Json -Depth 5

Set-Content -Path (Join-Path $orchestratorOut "appsettings.Production.json") -Value $appSettingsProd -Encoding UTF8
Write-Ok "appsettings.Production.json escrito (connection string + CORS para $pdaUrl / $controllerUrl)"

# -------------------------------------------------------------------
# 4. Compilar pda e controller
# -------------------------------------------------------------------

function Build-Frontend([string]$Name, [int]$Port) {
    Write-Step "A compilar $Name"
    $projDir = Join-Path $SourceRoot $Name
    $envFile = Join-Path $projDir ".env.production"
    $orchestratorUrl = "http://${HostName}:${OrchestratorPort}"
    Set-Content -Path $envFile -Value "VITE_ORCHESTRATOR_URL=$orchestratorUrl" -Encoding UTF8
    Write-Ok "$envFile -> VITE_ORCHESTRATOR_URL=$orchestratorUrl"

    Push-Location $projDir
    try {
        & npm install
        if ($LASTEXITCODE -ne 0) { throw "npm install falhou em $Name (código $LASTEXITCODE)." }
        & npm run build
        if ($LASTEXITCODE -ne 0) { throw "npm run build falhou em $Name (código $LASTEXITCODE)." }
    }
    finally {
        Pop-Location
    }

    $distDir = Join-Path $projDir "dist"
    $outDir = Join-Path $InstallRoot $Name
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    & robocopy $distDir $outDir /MIR /NFL /NDL /NJH /NJS | Out-Null
    Write-Ok "$Name compilado e copiado para $outDir"
}

if (Test-Command "npm") {
    Build-Frontend -Name "pda" -Port $PdaPort
    Build-Frontend -Name "controller" -Port $ControllerPort
}
else {
    Write-Warn2 "npm indisponível -- pda/controller não foram compilados. Instala o Node.js e corre este script outra vez (ou só a secção 4, manualmente)."
}

# -------------------------------------------------------------------
# 5. Sites e Application Pools no IIS
# -------------------------------------------------------------------

Write-Step "A configurar o IIS"

Import-Module WebAdministration -ErrorAction Stop

function Ensure-AppPool([string]$Name, [bool]$NoManagedCode) {
    if (-not (Test-Path "IIS:\AppPools\$Name")) {
        New-WebAppPool -Name $Name | Out-Null
        Write-Ok "Application pool '$Name' criado"
    }
    else {
        Write-Ok "Application pool '$Name' já existia"
    }
    if ($NoManagedCode) {
        Set-ItemProperty "IIS:\AppPools\$Name" -Name managedRuntimeVersion -Value ""
    }
    Set-ItemProperty "IIS:\AppPools\$Name" -Name startMode -Value "AlwaysRunning"
}

function Ensure-Site([string]$Name, [string]$PhysicalPath, [int]$Port, [string]$AppPool) {
    if (-not (Test-Path "IIS:\Sites\$Name")) {
        New-WebSite -Name $Name -PhysicalPath $PhysicalPath -Port $Port -ApplicationPool $AppPool | Out-Null
        Write-Ok "Site '$Name' criado (porta $Port, pool '$AppPool')"
    }
    else {
        Set-ItemProperty "IIS:\Sites\$Name" -Name physicalPath -Value $PhysicalPath
        Set-ItemProperty "IIS:\Sites\$Name" -Name applicationPool -Value $AppPool
        Write-Ok "Site '$Name' já existia -- caminho/pool atualizados"
    }
}

Ensure-AppPool -Name "WOPA-Orchestrator" -NoManagedCode $true
Ensure-Site -Name "WOPA-Orchestrator" -PhysicalPath $orchestratorOut -Port $OrchestratorPort -AppPool "WOPA-Orchestrator"
# Connection string também como variável de ambiente do pool (mais seguro
# do que só o ficheiro) -- suportado em Windows Server 2019+ com o
# hotfix do IIS / nativo em Server 2022. Se o comando abaixo falhar por a
# funcionalidade não estar disponível, o appsettings.Production.json (passo
# 3) já chega para a app arrancar.
try {
    Add-WebConfigurationProperty -PSPath "IIS:\AppPools\WOPA-Orchestrator" -Filter "environmentVariables" -Name "." `
        -Value @{name = "ConnectionStrings__Wopa"; value = $connectionString } -ErrorAction Stop
    Write-Ok "Connection string também definida como variável de ambiente do pool"
}
catch {
    Write-Warn2 "Não consegui definir a variável de ambiente do pool ($($_.Exception.Message)) -- sem problema, o appsettings.Production.json já tem a connection string."
}

if (Test-Path (Join-Path $InstallRoot "pda")) {
    Ensure-AppPool -Name "WOPA-Static" -NoManagedCode $false
    Ensure-Site -Name "WOPA-PDA" -PhysicalPath (Join-Path $InstallRoot "pda") -Port $PdaPort -AppPool "WOPA-Static"
}
if (Test-Path (Join-Path $InstallRoot "controller")) {
    Ensure-AppPool -Name "WOPA-Static" -NoManagedCode $false
    Ensure-Site -Name "WOPA-Controller" -PhysicalPath (Join-Path $InstallRoot "controller") -Port $ControllerPort -AppPool "WOPA-Static"
}

Write-Host "  A reiniciar os application pools..."
Restart-WebAppPool -Name "WOPA-Orchestrator" -ErrorAction SilentlyContinue
Restart-WebAppPool -Name "WOPA-Static" -ErrorAction SilentlyContinue

# -------------------------------------------------------------------
# 6. Verificação
# -------------------------------------------------------------------

Write-Step "A verificar a instalação"

Start-Sleep -Seconds 3
try {
    $health = Invoke-RestMethod -Uri "http://localhost:$OrchestratorPort/health" -TimeoutSec 15
    if ($health.status -eq "ok") {
        Write-Ok "orchestrator respondeu em http://localhost:$OrchestratorPort/health -> status=ok"
    }
    else {
        Write-Warn2 "orchestrator respondeu, mas com conteúdo inesperado: $($health | ConvertTo-Json -Compress)"
    }
}
catch {
    Write-Warn2 "Não consegui confirmar http://localhost:$OrchestratorPort/health ($($_.Exception.Message)). Consulta os logs em '$orchestratorOut\logs' (ativa stdoutLogEnabled no web.config se a pasta não existir -- ver DEPLOY.md secção 5)."
}

Write-Host ""
Write-Host "=== Instalação concluída ===" -ForegroundColor Cyan
Write-Host "  orchestrator:  http://${HostName}:${OrchestratorPort}/health"
Write-Host "  pda:           http://${HostName}:${PdaPort}"
Write-Host "  controller:    http://${HostName}:${ControllerPort}"
Write-Host ""
Write-Host "Login de exemplo (dados de seed): operador 42, PIN 1234." -ForegroundColor DarkGray

}
catch {
    $script:failed = $true
    Write-Host ""
    Write-Host "=== ERRO -- a instalação parou ===" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Detalhe completo:" -ForegroundColor DarkGray
    Write-Host ($_ | Out-String) -ForegroundColor DarkGray
}
finally {
    Wait-BeforeExit
}

# Fora do try/catch de propósito: garante que o processo termina com
# código de saída != 0 quando algo falhou -- essencial para o GitHub
# Actions (ou qualquer automação) saber que o deploy falhou, em vez de
# reportar sucesso só porque o script chegou ao fim sem exceção por
# apanhar.
if ($script:failed) { exit 1 }
