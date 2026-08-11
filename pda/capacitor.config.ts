import type { CapacitorConfig } from "@capacitor/cli";

// URL do orchestrator/pda real, dentro da rede interna da empresa (ADR-023
// -- sem domínio público, o pda vai continuar sempre em HTTP/IP interno,
// nunca em HTTPS). Parametrizável por variável de ambiente para não obrigar
// a editar este ficheiro a cada instalação -- mas o valor por omissão tem
// de ser mudado para o IP/hostname real do servidor antes de compilar.
const PDA_URL = process.env.WOPA_PDA_URL ?? "http://172.16.4.15:8081";

const config: CapacitorConfig = {
  appId: "pt.grestel.wopa.pda",
  appName: "WOPA PDA",
  webDir: "dist",
  server: {
    // O WebView carrega sempre a app ao vivo a partir do servidor -- não
    // há código nenhum embrulhado no APK. É assim que a atualização
    // automática funciona sem qualquer mecanismo extra: cada arranque
    // busca a versão mais recente do pda tal como um browser normal.
    url: PDA_URL,
    cleartext: true,
    // Restringe a navegação do WebView só ao host interno -- mesmo numa
    // rede interna, não faz sentido o WebView poder navegar para fora.
    allowNavigation: [new URL(PDA_URL).hostname],
  },
};

export default config;
