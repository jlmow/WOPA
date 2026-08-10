# Deployment do orchestrator no IIS

Este guia cobre o `orchestrator` (a API). Os frontends (`pda`, `controller`)
são só ficheiros estáticos — a secção 4 explica como os publicar a seguir
ao mesmo padrão.

Confirmei aqui que `dotnet publish` já gera o `web.config` correto para
IIS automaticamente (hosting in-process, sem precisar de tocar no
projeto) — não há nada a ajustar no código para isto funcionar.

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
- **Base de dados**: corre `database/schema.sql` no SQL Server do
  cliente primeiro (cria a BD `WOPA` e o schema completo). Depois, o
  `orchestrator` precisa da connection string real — cria
  `appsettings.Production.json` ao lado de `appsettings.json` com:
  ```json
  { "ConnectionStrings": { "Wopa": "Server=<servidor>;Database=WOPA;User Id=<user>;Password=<pass>;TrustServerCertificate=True;" } }
  ```
  ou define a variável de ambiente `ConnectionStrings__Wopa` no
  Application Pool do IIS (mais seguro do que deixar a password em
  ficheiro). **Nunca uses a connection string de
  `appsettings.Development.json`** — essa aponta para um contentor
  Docker local usado só para testar isto em desenvolvimento, não é o
  servidor do cliente.
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

**Importante para o `pda`**: já tem um `public/web.config` com a regra
de SPA fallback (serve sempre `index.html` em rotas desconhecidas, para
`/login`, `/modulos`, etc. funcionarem em refresh) — é copiado
automaticamente para `dist/` no build, não precisas de o recriar. O
`controller` ainda não tem este `web.config` — cria um igual em
`controller/public/web.config` antes do primeiro deployment em IIS
(o ficheiro do `pda` serve de modelo).

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
