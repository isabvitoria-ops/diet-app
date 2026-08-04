import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { viteSingleFile } from "vite-plugin-singlefile";
import path from "node:path";
import { readFileSync, writeFileSync } from "node:fs";

/**
 * Build de demonstração: o mesmo app, empacotado num único HTML para poder
 * ser publicado num link.
 *
 * Três diferenças em relação ao build de produção (vite.config.ts), todas
 * impostas por hospedar uma página só:
 *   1. Sem Service Worker/PWA — não há o que pré-cachear num arquivo único.
 *   2. Rota por hash (ver demo/main.demo.tsx) — não há servidor para
 *      responder /paciente numa recarga.
 *   3. Fontes embutidas como data URI — a CSP da página publicada barra
 *      host externo, e um @import do Google Fonts cairia calado no fallback.
 *
 * O CSS do app (tokens/patient/nutri) entra intacto; nada de design muda.
 */
const fontesEmbutidas = readFileSync(path.resolve(__dirname, "fontes-embutidas.css"), "utf8");

export default defineConfig({
  root: __dirname,
  plugins: [
    react(),
    viteSingleFile({ removeViteModuleLoader: true }),
    {
      /**
       * Troca o @import do Google Fonts pelos @font-face com data URI.
       *
       * Roda no bundle final, não em `transform`: o Vite resolve @import de
       * CSS na própria pipeline antes de um transform de plugin enxergar
       * tokens.css, e a regra passava batida — o HTML saía com o link
       * externo, que a CSP da página publicada barra sem avisar.
       */
      name: "fontes-offline",
      enforce: "post",
      closeBundle() {
        const saida = path.resolve(__dirname, "../dist-demo/index.html");
        const html = readFileSync(saida, "utf8");
        // O minificador tira o `url()` e o espaço: sai `@import"https://…"`.
        const IMPORT_GOOGLE = /@import\s*(?:url\()?\s*["']https:\/\/fonts\.googleapis[^"']*["']\s*\)?\s*;?/g;
        if (!IMPORT_GOOGLE.test(html)) {
          throw new Error(
            "Nenhum @import do Google Fonts no HTML gerado — verifique o seletor antes de publicar; sem isto a página sai com fonte de host externo, que a CSP bloqueia.",
          );
        }
        IMPORT_GOOGLE.lastIndex = 0;
        const comFontes = html.replace(IMPORT_GOOGLE, fontesEmbutidas);
        if (/https:\/\/fonts\.(googleapis|gstatic)/.test(comFontes)) {
          throw new Error("Sobrou referência a fonte externa no HTML gerado.");
        }
        writeFileSync(saida, comFontes);
      },
    },
  ],
  resolve: { alias: { "@": path.resolve(__dirname, "../src") } },
  build: {
    outDir: path.resolve(__dirname, "../dist-demo"),
    emptyOutDir: true,
    cssCodeSplit: false,
    assetsInlineLimit: 100_000_000,
  },
});
