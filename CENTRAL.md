# Central do Paciente

Ferramenta de consulta do paciente: troca de alimentos com cálculo automático,
estratégias para comer fora, lista de substituições por grupo, guias e favoritos.

Abre em **`/central`**, sem login. É um app separado do acompanhamento
(`/paciente` e `/nutricionista`), que continua exatamente como estava.

---

## 1. Stack

| Camada | Escolha | Por quê |
|---|---|---|
| Build | Vite | Já era a do projeto |
| Interface | React 18 + TypeScript | Já era a do projeto |
| Rotas | react-router-dom | Já era dependência |
| Estado | Zustand | Já era dependência; usado só em favoritos e histórico |
| Estilo | CSS puro com variáveis | Sem framework: a identidade visual mora em um bloco de variáveis |
| Testes | `node:test` nativo | Zero dependência nova |

**Nenhuma dependência nova foi instalada.** A fonte de título (Fraunces) é
servida pelo próprio app, em `public/fonts/`, sem pedir nada ao Google.

---

## 2. Como o código está organizado

```
src/central/
  CentralApp.tsx      A casca: rotas + navegação. Sem regra de negócio.
  rotas.ts            Todos os caminhos em um lugar só.

  data/               OS DADOS — é aqui que você escreve conteúdo.
    unidades.ts         g, ml, unidade, colher, fatia…
    grupos.ts           Carboidratos, proteínas, vegetais livres…
    alimentos.ts        Cada alimento e sua porção de referência.
    equivalencias.ts    Trocas que não saem da razão entre porções.
    comerFora.ts        Hambúrguer, japonesa, massas, doces…
    guias.ts            Os temas dos guias.
    catalogo.ts         A porta de leitura. As telas só falam com ela.
    indiceBusca.ts      Monta a busca global a partir de tudo acima.

  utils/              AS CONTAS — lógica pura, sem tela.
    calculoTroca.ts     O motor da Troca Inteligente.
    porcoes.ts          Porções, frações e combinações.
    medidas.ts          Conversão de unidade e arredondamento.
    buscaAlimentos.ts   Autocomplete dos campos de alimento.
    buscaGlobal.ts      A busca de tudo.
    armazenamento.ts    localStorage por trás de uma interface trocável.

  pages/              UMA TELA POR ARQUIVO.
  components/         Peças reutilizadas entre telas.
  hooks/              Favoritos e trocas recentes.
  types/              O contrato de todos os dados.
  styles/central.css  A identidade visual inteira.
```

A regra que mantém isso saudável: **tela não conhece dado, dado não conhece
tela, e conta nenhuma acontece dentro de componente**. Se um número aparece
na interface, ele veio de uma função em `utils/`.

---

## 3. Onde está cada coisa

| O que | Arquivo |
|---|---|
| Alimentos | `src/central/data/alimentos.ts` |
| Equivalências | `src/central/data/equivalencias.ts` |
| Grupos e a regra dos vegetais livres | `src/central/data/grupos.ts` |
| Conteúdo de comer fora | `src/central/data/comerFora.ts` |
| Guias | `src/central/data/guias.ts` |
| Unidades de medida | `src/central/data/unidades.ts` |
| Cores, tipografia e espaçamento | `src/central/styles/central.css` |

Cada um desses arquivos começa com um comentário mostrando o formato e um
exemplo pronto para copiar.

---

## 4. Como acrescentar um alimento

Em `data/alimentos.ts`, some uma linha na lista:

```ts
alimento({
  id: "batata-doce-cozida",      // minúsculas, sem acento, com hífen
  nome: "Batata-doce cozida",
  grupoId: "carboidratos",       // ver data/grupos.ts
  porcao: { quantidade: 120, unidadeId: "g" },
  semGluten: true,
  semLactose: true,
  tags: ["batata", "tuberculo"],
}),
```

Só isso. O alimento passa a aparecer na lista do grupo, na busca global e —
por ter porção — **em todas as trocas dentro do grupo**, sem você escrever
nenhuma equivalência.

Se ainda não souber a porção, omita `porcao`: o alimento aparece marcado como
"em cadastro" e fica fora da calculadora até você preencher.

**Para oferecer colher, fatia ou unidade** naquele alimento, diga quanto vale
uma delas:

```ts
medidas: [
  { unidadeId: "colher-sopa", equivalenteNaBase: 25 },  // 1 colher = 25 g
],
```

O seletor de unidade só mostra o que está cadastrado ali.

---

## 5. Como acrescentar uma equivalência

Você só precisa escrever uma quando o valor **não** for a razão entre as
porções — por exemplo quando a lista de substituição trouxer um número
próprio para aquele par. Em `data/equivalencias.ts`:

```ts
{
  id: "pao-para-tapioca",
  origemAlimentoId: "pao",
  destinoAlimentoId: "tapioca",
  regra: {
    tipo: "proporcional",
    de: { quantidade: 50, unidadeId: "g" },
    para: { quantidade: 40, unidadeId: "g" },
  },
  bidirecional: true,
  fonte: "Lista de substituição",
  observacao: null,
},
```

**Trocas que não escalam em linha reta** usam outro formato:

```ts
regra: {
  tipo: "tabela",
  unidadeOrigemId: "g",
  unidadeDestinoId: "unidade",
  pontos: [ { de: 50, para: 1 }, { de: 120, para: 2 } ],
}
```

O sistema interpola entre os pontos e **nunca extrapola** além deles — fora da
faixa cadastrada ele trava no extremo e avisa na tela.

Como o cálculo decide (nesta ordem):
1. equivalência cadastrada no sentido pedido;
2. a mesma equivalência lida ao contrário, se for bidirecional;
3. a razão entre as porções dos dois alimentos, dentro do mesmo grupo;
4. nada disso fechou → a tela diz o que está faltando, e não mostra número.

---

## 6. Como acrescentar um restaurante ou categoria

Em `data/comerFora.ts`. O mínimo para a categoria já aparecer na grade e na
busca:

```ts
{
  id: "poke",
  nome: "Poke",
  resumo: null,
  icone: "restaurante",          // ver components/Icone.tsx
  ordem: 10,
  status: "em-preparacao",
  introducao: null,
  decisoes: [],
  lembretes: [],
  tags: ["poke", "havaiano"],
},
```

Para publicar, mude `status` para `"publicado"` e preencha as decisões — cada
decisão é uma escolha real da refeição, com suas opções classificadas:

```ts
decisoes: [
  {
    id: "base",
    titulo: "A base",
    pergunta: "Sobre o que o prato é montado?",
    opcoes: [
      {
        id: "base-arroz",
        titulo: "Arroz",
        descricao: "Texto seu, do seu jeito.",
        nivel: "melhor",               // "melhor" | "boa" | "ocasional" | null
        energia: { kcal: 210, mostrarKcal: false, observacao: null },
        detalhes: ["Marcador curto"],
        tags: ["arroz"],
      },
    ],
  },
],
```

`kcal` fica guardado mesmo com `mostrarKcal: false`. O número existe no
sistema e só aparece para o paciente quando você ligar, item a item.

---

## 7. Como acrescentar um guia

Em `data/guias.ts`, troque a linha curta por um objeto completo:

```ts
{
  id: "refeicao-livre",
  titulo: "Refeição livre",
  tema: "No dia a dia",           // agrupa na listagem
  resumo: "Uma linha que aparece na lista.",
  ordem: 1,
  status: "publicado",
  secoes: [
    {
      id: "como-funciona",
      titulo: "Como funciona",
      paragrafos: ["Um parágrafo por item da lista."],
      itens: ["Marcador curto", "Outro marcador"],
    },
  ],
  tags: ["refeicao livre"],
},
```

Enquanto `secoes` estiver vazio, o guia aparece como "em breve" — de propósito.

---

## 8. Como mudar a identidade visual

Tudo mora no primeiro bloco de `src/central/styles/central.css`:

```css
.central {
  --primary: #3a6355;
  --primary-dark: #274539;
  --background: #f6f4f1;
  --surface: #ffffff;
  --text: #1f1d1b;
  --text-muted: #655f59;
  --border: #e6e1d9;
  --success: #3d6650;
  --warning: #7d5c14;
  --danger: #8f4034;
  --radius: 20px;
  --font-display: "Fraunces", Georgia, serif;
  --font-body: "Public Sans", system-ui, sans-serif;
}
```

Nenhuma regra do arquivo escreve cor no meio do caminho — trocar essas linhas
troca o app inteiro.

Depois de mexer nas cores, rode `npm test`: há um teste que confere o
contraste de cada par que aparece na tela contra a régua da WCAG e diz qual
combinação reprovou e por quanto. Trocar de paleta sem tornar o texto ilegível
deixa de depender de olhar.

**Trocar a fonte de título:** baixe o `.woff2` para `public/fonts/` e ajuste os
dois blocos `@font-face` no topo do mesmo arquivo.

---

## 9. Como rodar

```bash
npm install
npm run dev        # http://localhost:5173/central
```

| Comando | O que faz |
|---|---|
| `npm run dev` | Servidor de desenvolvimento |
| `npm test` | Testes do cálculo e do contraste de cores |
| `npm run typecheck` | Confere os tipos |
| `npm run lint` | Confere o estilo do código |
| `npm run build` | Build de produção |
| `npm run preview` | Serve o build localmente |

Para ver no celular na mesma rede: `npm run dev -- --host` e abra o endereço
de rede que aparecer, acrescentando `/central`.

---

## 10. O que ainda não tem dado

O briefing pediu para não inventar valor nutricional nem equivalência. Então,
por ora, só está cadastrado o que veio de você:

- **1 equivalência**: 100 g de arroz = 80 g de macarrão.
- **2 alimentos com porção**: arroz (100 g, informado por você) e macarrão
  (80 g, aritmética direta sobre a equivalência acima).
- **27 vegetais livres**, com a regra de 150 g no almoço e no jantar.
- **Comer fora**: as opções de comida japonesa e as duas montagens de
  hambúrguer que você descreveu; massas e doces estão com as decisões
  mapeadas e as opções em branco.
- **Guias**: os 11 temas reservados, todos sem conteúdo.

Tudo o mais aparece marcado como "em cadastro" ou "em preparação". Conforme
você for passando o material, é só preencher os arquivos de `data/` — a
interface inteira já está pronta para o conteúdo.

---

## 11. Preparado para depois

- **Banco de dados**: as telas leem por `data/catalogo.ts`. Trocar JSON por
  Supabase é reimplementar aquelas funções devolvendo `Promise` — nenhum
  componente conhece a origem do dado.
- **Login e plano por paciente**: nada na Central assume "um só paciente". Os
  favoritos já são uma tabela (`id`, `tipo`, `referência`, `data`), o que
  torna a migração de localStorage para conta um espelhamento, não um
  redesenho.
- **Frações de porção**: `utils/porcoes.ts` já calcula combinações do tipo
  "0,5 porção de arroz + 0,5 de abóbora"; falta só a tela.
- **Regras não lineares**: o motor já aceita tabela de pontos e regra fixa
  além da proporcional. Acrescentar um quarto tipo é somar um membro ao tipo
  e um caso na função, sem tocar em tela.
