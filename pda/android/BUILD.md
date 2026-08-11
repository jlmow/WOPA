# Compilar o WOPA PDA para Android (ADR-023)

Este `android/` é um wrapper Capacitor muito fino: não leva o código do
`pda` lá dentro, só abre um `WebView` apontado sempre para o servidor real
(`capacitor.config.ts`). Por isso a app **atualiza-se sozinha a cada
arranque** — cada vez que abre, carrega a versão mais recente do
`pda` publicada no IIS, tal como um browser normal. Não precisas de
recompilar o `.apk` sempre que o `pda` muda — só quando o próprio wrapper
mudar (ex.: ícone, nome, ou o host do servidor).

Isto não corre no sandbox onde o resto do WOPA foi desenvolvido (sem
acesso à rede do Android SDK) — tens de compilar numa máquina tua com
Android Studio.

## Pré-requisitos (na tua máquina)

- [Android Studio](https://developer.android.com/studio) instalado (inclui
  o Android SDK) — ou só o `cmdline-tools` + `sdkmanager` se preferires
  sem o IDE.
- Node.js (o mesmo que já usas para o `pda`).

## 1. Confirmar o host do servidor

Edita `pda/capacitor.config.ts` e confirma que `PDA_URL` aponta para o
host/porta reais onde o `pda` está publicado (por omissão
`http://172.16.4.15:8081`). Se mudar, atualiza também o `<domain>` em
`pda/android/app/src/main/res/xml/network_security_config.xml` para o
mesmo host — os dois têm de bater certo, ou o `WebView` bloqueia o
pedido (cleartext só é permitido para esse host específico, de propósito).

## 2. Compilar o pda e sincronizar com o Android

```powershell
cd pda
npm install
npm run build
npx cap sync android
```

`cap sync` copia o `dist/` mais recente para dentro do projeto Android
(usado só como fallback offline caso o `WebView` não consiga alcançar o
servidor no arranque) e atualiza as dependências nativas.

## 3. Abrir no Android Studio e compilar o APK

```powershell
npx cap open android
```

No Android Studio: **Build → Generate Signed Bundle / APK → APK**.
Cria (ou reutiliza) um keystore de assinatura — guarda-o em local seguro,
**não o commites ao repositório** (`android/.gitignore` já o exclui, mas
convém confirmar). Escolhe `release`, compila.

Alternativa por linha de comandos (assinatura via `key.properties`, ver
documentação do Gradle Android para o formato):

```powershell
cd android
./gradlew assembleRelease
```

O `.apk` fica em `android/app/build/outputs/apk/release/`.

## 4. Publicar o APK para o botão "Instalar em Android"

O cabeçalho do `pda` (todos os ecrãs, ver `RootLayout.tsx`) já tem uma
ligação "Instalar em Android" que aponta para `/wopa-pda.apk`. Copia o
`.apk` compilado para `pda/public/wopa-pda.apk` antes de fazer
`npm run build` do `pda` — fica servido como ficheiro estático, e um
operador com Android consegue abrir o `pda` no Chrome, tocar no botão e
instalar diretamente (pode ser preciso ativar "Instalar de fontes
desconhecidas" da primeira vez, por não vir da Play Store).

## Notas

- Sem HTTPS/domínio público (rede interna da empresa, ADR-023), por isso
  isto não é um TWA verificado — é um `WebView` normal com cleartext
  autorizado só para o host do servidor. Funciona igual em uso interno,
  só não tem o "chrome-less" 100% garantido de um TWA verificado.
- Se mudares o host do servidor depois de já teres instalado o APK em
  telefones, tens de recompilar e reinstalar (o host está fixo no APK,
  ao contrário do resto da app que atualiza sozinho).
