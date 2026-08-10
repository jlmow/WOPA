# Instalar o pda num PDA Android — prova de conceito

Não é preciso build nativo nem loja de apps — é uma PWA. Instalar é
abrir a página no Chrome do dispositivo e "adicionar ao ecrã principal".

## 1. Ter o orchestrator acessível na rede do PDA

O PDA tem de conseguir alcançar o `orchestrator` pela rede Wi-Fi do
armazém — não pode ser `localhost` (isso só existe no ponto de vista do
próprio PDA). Duas opções:

- **Já tens IIS a correr** (ver `orchestrator/DEPLOY.md`): usa esse
  endereço, ex. `http://api.wopa.local` ou `http://192.168.1.50:8080`.
- **Prova de conceito rápida, sem IIS**: numa máquina Windows/Linux na
  mesma rede Wi-Fi do armazém:
  ```
  cd orchestrator/src/Orchestrator.Api
  dotnet run --urls http://0.0.0.0:5080
  ```
  Confirma o IP dessa máquina na rede (`ipconfig` / `ifconfig`) — vais
  precisar dele nos passos seguintes.

## 2. Fazer o build do pda apontado para esse endereço

```bash
cd pda
echo "VITE_ORCHESTRATOR_URL=http://<IP-ou-domínio-do-orchestrator>:5080" > .env.production
npm install
npm run build
```

Isto gera `dist/` — a app já compilada, a apontar para o servidor
certo (não para `localhost`).

## 3. Servir esses ficheiros para o PDA conseguir abrir

Na mesma máquina (ou noutra na rede):

```bash
npx serve dist -l 5173 --host 0.0.0.0
```

Confirma o IP desta máquina também. Se o `orchestrator` e o `pda`
estiverem na mesma máquina, é o mesmo IP, portas diferentes.

## 4. No PDA Android

1. Liga o PDA à mesma rede Wi-Fi.
2. Abre o **Chrome** (tem de ser Chrome ou outro browser Chromium —
   Firefox Android não suporta instalação de PWA da mesma forma).
3. Navega para `http://<IP da máquina>:5173`.
4. Confirma que a app carrega e o indicador no topo mostra **"Ligado
   ao servidor"** — se mostrar "Sem ligação", confirma que o
   `orchestrator` está mesmo acessível desse IP a partir do PDA (testa
   `http://<IP>:5080/health` diretamente no Chrome do PDA).
5. Menu do Chrome (⋮) → **"Instalar aplicação"** (ou "Adicionar ao ecrã
   principal", consoante a versão do Chrome). Confirma.
6. A app fica com ícone próprio no ecrã principal do PDA, a abrir sem
   a barra de endereço do browser (modo `standalone`, já configurado
   no `vite.config.ts`).

## 5. Testar o fluxo

1. Abre a app pelo ícone instalado.
2. Login: qualquer número de operador (ainda sem validação real no
   backend).
3. Módulos → Picking (Transporte/Abastecimento aparecem desativados
   "em breve" — é esperado).
4. Zona → escolhe uma.
5. Deve entrar logo na primeira linha da missão de exemplo. Testa:
   - Ler o código de barras certo (usa o leitor físico do PDA, ou
     escreve manualmente no campo se estiveres só a testar) — o
     progresso avança sozinho.
   - Ativa o modo avião no PDA a meio de uma leitura — confirma que
     continua a funcionar (é a prova de conceito do offline, ADR-007) e
     que o indicador de ligação muda para "Sem ligação ao servidor".
   - Desativa o modo avião — os dados devem sincronizar sozinhos, sem
     tocares em nada.

## Notas

- Este guia usa dados de exemplo fixos (uma única missão, sempre a
  mesma). Não há ainda um ecrã para gerar missões reais a partir de
  Ordens de Preparação — ver ARCHITECTURE.md, ADR-008.
- Se precisares de repetir o teste do zero, `POST /api/picking/reset`
  no `orchestrator` repõe os dados de exemplo (mas não limpa o que já
  está guardado localmente no PDA — para isso, desinstala a app do
  ecrã principal e volta a instalar, ou limpa os dados do site pelo
  Chrome).
