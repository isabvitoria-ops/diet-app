import type { CategoriaComerFora } from "@/central/types";

/**
 * Conteúdo de "Comer fora" (§13 a §16).
 *
 * O que está preenchido veio do que a nutricionista descreveu dos próprios
 * materiais. O que ela ainda não passou está como decisão sem opções ou
 * categoria `em-preparacao` — a tela mostra isso com calma, sem fingir que
 * o conteúdo existe (§29).
 *
 * COMO ACRESCENTAR UM RESTAURANTE / CATEGORIA
 * -------------------------------------------
 * Some um objeto na lista. O mínimo viável é id, nome, icone, ordem e
 * `status: "em-preparacao"` — ele já aparece na grade e na busca global.
 * Para publicar, mude o status e preencha `decisoes`:
 *
 *   decisoes: [
 *     {
 *       id: "molho",
 *       titulo: "O molho",
 *       pergunta: "Como o prato vem temperado?",
 *       opcoes: [
 *         {
 *           id: "molho-tomate",
 *           titulo: "À base de tomate",
 *           descricao: "Texto curto, do seu jeito.",
 *           nivel: "melhor",            // "melhor" | "boa" | "ocasional" | null
 *           energia: { kcal: 180, mostrarKcal: false, observacao: null },
 *           detalhes: ["Marcador curto", "Outro marcador"],
 *           tags: ["molho"],
 *         },
 *       ],
 *     },
 *   ]
 *
 * `energia.kcal` fica guardado mesmo com `mostrarKcal: false` — o número
 * existe no sistema e só aparece na tela quando você decidir, item a item (§16).
 */
export const CATEGORIAS_COMER_FORA: CategoriaComerFora[] = [
  {
    id: "hamburguer",
    nome: "Hambúrguer",
    resumo: "Como montar o lanche do jeito que cabe no seu dia.",
    icone: "hamburguer",
    ordem: 1,
    status: "publicado",
    introducao:
      "Compare as montagens antes de pedir. A diferença costuma estar no número de camadas, não no lanche em si.",
    decisoes: [
      {
        id: "montagem",
        titulo: "A montagem do lanche",
        pergunta: "Quantas camadas o lanche tem?",
        opcoes: [
          {
            id: "hamburguer-simples",
            titulo: "Montagem mais simples",
            descricao: null,
            nivel: "melhor",
            energia: null,
            detalhes: [],
            tags: ["hamburguer", "simples"],
          },
          {
            id: "hamburguer-denso",
            titulo: "Combinações mais densas em energia",
            descricao: null,
            nivel: "ocasional",
            energia: null,
            detalhes: [],
            tags: ["hamburguer", "duplo", "bacon", "cheddar"],
          },
        ],
      },
    ],
    lembretes: [],
    tags: ["hamburguer", "lanche", "burger"],
  },
  {
    id: "japonesa",
    nome: "Comida japonesa",
    resumo: "Entradas, pratos e o que costuma pesar no rodízio.",
    icone: "japonesa",
    ordem: 2,
    status: "publicado",
    introducao:
      "Comece pelas entradas, escolha o prato principal e deixe as preparações fritas e os molhos cremosos como parte menor da refeição.",
    decisoes: [
      {
        id: "entradas",
        titulo: "Entradas",
        pergunta: "Por onde começar?",
        opcoes: [
          { id: "sunomono", titulo: "Sunomono", descricao: null, nivel: "melhor", energia: null, detalhes: [], tags: ["sunomono", "pepino"] },
          { id: "missoshiro", titulo: "Missoshiro", descricao: null, nivel: "melhor", energia: null, detalhes: [], tags: ["missoshiro", "sopa", "miso"] },
          { id: "edamame", titulo: "Edamame", descricao: null, nivel: "melhor", energia: null, detalhes: [], tags: ["edamame", "soja"] },
        ],
      },
      {
        id: "principal",
        titulo: "O prato principal",
        pergunta: "O que pedir depois das entradas?",
        opcoes: [
          { id: "sashimi", titulo: "Sashimi", descricao: null, nivel: "melhor", energia: null, detalhes: [], tags: ["sashimi", "peixe"] },
          { id: "niguiri", titulo: "Niguiri", descricao: null, nivel: "boa", energia: null, detalhes: [], tags: ["niguiri", "sushi"] },
        ],
      },
      {
        id: "ocasionais",
        titulo: "Preparações fritas e molhos cremosos",
        pergunta: "E os itens que aparecem no rodízio?",
        opcoes: [
          { id: "fritos", titulo: "Preparações fritas", descricao: null, nivel: "ocasional", energia: null, detalhes: [], tags: ["frito", "tempura", "hot"] },
          { id: "molhos-cremosos", titulo: "Molhos cremosos", descricao: null, nivel: "ocasional", energia: null, detalhes: [], tags: ["molho", "cremoso"] },
        ],
      },
    ],
    lembretes: [],
    tags: ["japonesa", "japones", "sushi", "sashimi", "rodizio", "temaki"],
  },
  {
    id: "massas",
    nome: "Massas",
    resumo: "Quantidade da massa, proteína e molho.",
    icone: "massas",
    ordem: 3,
    status: "publicado",
    introducao: "Três escolhas definem o prato: quanto de massa, se entra proteína e qual molho acompanha.",
    decisoes: [
      { id: "quantidade", titulo: "Quantidade da massa", pergunta: "Quanto de massa vem no prato?", opcoes: [] },
      { id: "proteina", titulo: "A proteína", pergunta: "O prato inclui proteína?", opcoes: [] },
      { id: "molho", titulo: "O molho", pergunta: "Qual molho acompanha?", opcoes: [] },
    ],
    lembretes: [],
    tags: ["massa", "macarrao", "italiano", "molho"],
  },
  {
    id: "doces",
    nome: "Doces e sobremesas",
    resumo: "Tipos de sobremesa e o tamanho da porção.",
    icone: "doces",
    ordem: 4,
    status: "publicado",
    introducao: "A escolha da sobremesa e o tamanho da porção contam juntos.",
    decisoes: [
      { id: "tipo", titulo: "O tipo de sobremesa", pergunta: "Qual sobremesa está na mesa?", opcoes: [] },
      { id: "porcao", titulo: "A porção", pergunta: "Quanto vem servido?", opcoes: [] },
    ],
    lembretes: [],
    tags: ["doce", "sobremesa", "chocolate", "bolo"],
  },

  // Categorias já reservadas — aparecem na grade e na busca, ainda sem conteúdo.
  { id: "subway", nome: "Subway", resumo: null, icone: "sanduiche", ordem: 5, status: "em-preparacao", introducao: null, decisoes: [], lembretes: [], tags: ["subway", "sanduiche", "sub"] },
  { id: "pizza", nome: "Pizza", resumo: null, icone: "pizza", ordem: 6, status: "em-preparacao", introducao: null, decisoes: [], lembretes: [], tags: ["pizza", "pizzaria"] },
  { id: "acai", nome: "Açaí", resumo: null, icone: "acai", ordem: 7, status: "em-preparacao", introducao: null, decisoes: [], lembretes: [], tags: ["acai", "tigela"] },
  { id: "restaurantes", nome: "Restaurantes", resumo: null, icone: "restaurante", ordem: 8, status: "em-preparacao", introducao: null, decisoes: [], lembretes: [], tags: ["restaurante", "self service", "buffet", "por quilo"] },
  { id: "delivery", nome: "Delivery", resumo: null, icone: "delivery", ordem: 9, status: "em-preparacao", introducao: null, decisoes: [], lembretes: [], tags: ["delivery", "ifood", "entrega"] },
];

export const CATEGORIA_COMER_FORA_POR_ID: ReadonlyMap<string, CategoriaComerFora> = new Map(
  CATEGORIAS_COMER_FORA.map((c) => [c.id, c]),
);
