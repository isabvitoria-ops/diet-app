# Build de demonstração

Empacota o app inteiro num **único HTML** para poder ser aberto por link, sem
servidor. Serve para mostrar o produto rodando — não substitui o build de
produção.

```bash
npm run build:demo     # gera dist-demo/index.html (~944 KB)
```

`dist-demo/` é saída de build e não entra no git.

## O que muda em relação ao build de produção

Três diferenças, todas impostas por hospedar uma página só. **Nenhuma é de
design** — `tokens.css`, `patient.css` e `nutri.css` entram intactos.

| | Produção (`vite.config.ts`) | Demo (`demo/vite.config.demo.ts`) |
|---|---|---|
| Rota | `BrowserRouter` (`/paciente`) | `HashRouter` (`#/paciente`) |
| Service Worker | PWA com precache | nenhum |
| Fontes | `@import` do Google Fonts | `@font-face` com data URI |

### Rota por hash

Num arquivo único servido de um caminho fixo não existe servidor para devolver
o app quando alguém recarrega em `/paciente`. Por isso a rota vive no
fragmento.

Para não duplicar a tela, `App` recebe o roteador por parâmetro
(`<App Roteador={HashRouter} />` em `demo/main.demo.tsx`); o padrão continua
`BrowserRouter`, então produção não muda.

### Fontes embutidas

A CSP da página publicada bloqueia qualquer host externo. Um `@import` do
Google Fonts não daria erro visível — a página simplesmente cairia na fonte do
sistema, e a tipografia do produto sumiria sem ninguém notar.

`demo/fontes-embutidas.css` traz as 9 faces (subset latino, que cobre o
português) como base64. O plugin `fontes-offline` troca o `@import` pelas
`@font-face` no HTML gerado e **aborta o build** se sobrar referência externa.

Duas armadilhas que esse plugin já pagou:

- O minificador reescreve `@import url("…")` como `@import"…"`, sem o
  `url()`. Um padrão que exija `url(` passa batido.
- A troca precisa acontecer em `closeBundle`, no arquivo já escrito: o Vite
  resolve `@import` de CSS na própria pipeline, antes de um `transform` de
  plugin enxergar `tokens.css`.

Para regerar as fontes (ex.: ao mudar as famílias em `tokens.css`), baixe os
`woff2` do subset `latin` da URL do Google Fonts e reescreva o arquivo com os
`@font-face` apontando para `data:font/woff2;base64,…`.

## Antes de publicar

O build falha sozinho se sobrar fonte externa, mas o resto vale conferir no
navegador servindo `dist-demo/`:

- as duas aplicações abrem e navegam;
- `document.fonts` mostra as faces como `loaded` (não fallback);
- **zero requisições a host externo** — é o que a CSP exige.

Os dados são os mocks em memória: tudo que o visitante fizer some ao
recarregar, exceto o "confiar neste dispositivo" do MFA, que grava no
`localStorage`.
