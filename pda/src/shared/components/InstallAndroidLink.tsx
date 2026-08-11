// ADR-023: liga para o .apk estático (pda/public/wopa-pda.apk -- ver
// android/BUILD.md para o compilar). Escondido quando a app já está a
// correr dentro do wrapper Android instalado (window.Capacitor), para não
// mostrar "instalar" a quem já instalou.
declare global {
  interface Window {
    Capacitor?: { isNativePlatform?: () => boolean };
  }
}

export function InstallAndroidLink() {
  if (typeof window !== "undefined" && window.Capacitor?.isNativePlatform?.()) {
    return null;
  }

  return (
    <a className="install-android-link" href="/wopa-pda.apk" download data-testid="instalar-android">
      Instalar em Android
    </a>
  );
}
