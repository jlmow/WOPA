import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { VitePWA } from "vite-plugin-pwa";

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      registerType: "autoUpdate",
      manifest: {
        name: "WOPA Picking",
        short_name: "WOPA Picking",
        description: "Picking de encomendas para PDA — WOPA",
        start_url: ".",
        display: "standalone",
        orientation: "portrait",
        background_color: "#faf8f4",
        theme_color: "#1a1a1a",
        icons: [
          { src: "pwa-192.svg", sizes: "192x192", type: "image/svg+xml" },
          { src: "pwa-512.svg", sizes: "512x512", type: "image/svg+xml" },
        ],
      },
    }),
  ],
});
