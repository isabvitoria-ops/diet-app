import type { CategoriaComerFora, NivelEscolha, OpcaoComerFora, ValorEnergetico } from "@/central/types";

/**
 * Conteúdo de "Comer fora".
 *
 * Tudo aqui veio dos materiais da nutricionista — "Melhores escolhas para sua
 * refeição livre" — e nada foi completado por fora deles. Onde o material não
 * diz, o campo fica nulo e a tela mostra o estado de preparo, em vez de
 * inventar um número ou uma recomendação.
 *
 * A classificação em melhor escolha / boa opção / mais ocasional só aparece
 * onde o próprio material compara as opções. Nas listas em que ela apenas
 * apresenta alternativas equivalentes, `nivel` fica nulo: marcar uma cor ali
 * seria criar um julgamento que ela não fez.
 *
 * COMO ACRESCENTAR UM RESTAURANTE / CATEGORIA
 * -------------------------------------------
 * Pela tela: área da nutricionista → Conteúdos → Comer fora → Nova categoria.
 * Por aqui: some um objeto na lista e rode `npm run seed && npm run instalador`.
 */

interface EntradaOpcao {
  id: string;
  titulo: string;
  descricao?: string | null;
  nivel?: NivelEscolha | null;
  kcal?: number | null;
  mostrarKcal?: boolean;
  detalhes?: string[];
  tags?: string[];
}

function opcao(e: EntradaOpcao): OpcaoComerFora {
  const energia: ValorEnergetico | null =
    e.kcal === undefined && e.mostrarKcal === undefined
      ? null
      : { kcal: e.kcal ?? null, mostrarKcal: e.mostrarKcal ?? false, observacao: null };
  return {
    id: e.id,
    titulo: e.titulo,
    descricao: e.descricao ?? null,
    nivel: e.nivel ?? null,
    energia,
    detalhes: e.detalhes ?? [],
    tags: e.tags ?? [],
  };
}

export const CATEGORIAS_COMER_FORA: CategoriaComerFora[] = [
  // ---------------------------------------------------------------- refeição livre
  {
    id: "refeicao-livre",
    nome: "Refeição livre",
    resumo: "Como contar uma refeição completa e uma meia refeição.",
    icone: "taca",
    ordem: 1,
    status: "publicado",
    introducao:
      "Duas meias refeições equivalem a uma completa. Uma completa mais uma meia equivalem a uma refeição e meia. É com essa conta que as opções abaixo se encaixam na sua semana.",
    decisoes: [
      {
        id: "completas",
        titulo: "Refeições completas",
        pergunta: "Cada uma destas fecha uma refeição livre inteira.",
        observacoes: [],
        opcoes: [
          opcao({
            id: "completa-hamburguer",
            titulo: "Hambúrguer com batata frita pequena e refrigerante zero açúcar",
            tags: ["hamburguer", "lanche", "batata"],
          }),
          opcao({
            id: "completa-pizza",
            titulo: "Pizza",
            descricao: "3 fatias de massa fina, ou 2 fatias de massa grossa ou de borda recheada.",
            detalhes: [
              "Prefira opções com proteína e sem muita adição de queijo, como frango ou carne seca.",
            ],
            tags: ["pizza"],
          }),
          opcao({
            id: "completa-acai",
            titulo: "Açaí de 500 ml com banana e leite condensado",
            tags: ["acai", "banana"],
          }),
        ],
      },
      {
        id: "meias",
        titulo: "Meias refeições",
        pergunta: "Duas delas somam uma refeição completa.",
        observacoes: [],
        opcoes: [
          opcao({ id: "meia-acai", titulo: "Açaí de 300 ml com 1 fruta e leite condensado", tags: ["acai"] }),
          opcao({
            id: "meia-gelato",
            titulo: "Gelato: 1 copo médio com 2 sabores",
            descricao: "Bacio di Latte, Lullo, Mi Garba.",
            tags: ["gelato", "sorvete"],
          }),
          opcao({
            id: "meia-cookie",
            titulo: "1 cookie artesanal grande, estilo americano",
            descricao: "Mr. Cheney, American Day.",
            tags: ["cookie", "biscoito"],
          }),
          opcao({ id: "meia-bolo", titulo: "1 fatia média de bolo ou torta com calda", tags: ["bolo", "torta"] }),
          opcao({ id: "meia-temaki", titulo: "1 temaki simples, sem cream cheese", tags: ["temaki", "japonesa"] }),
          opcao({ id: "meia-brownie", titulo: "1 brownie com 1 bola de sorvete", tags: ["brownie", "sorvete"] }),
          opcao({
            id: "meia-milkshake",
            titulo: "Milkshake pequeno",
            descricao: "Bob's, McDonald's.",
            // O material traz este valor; ele fica guardado e só aparece se
            // a nutricionista ligar a exibição neste item (§18 do briefing).
            kcal: 330,
            mostrarKcal: false,
            tags: ["milkshake"],
          }),
        ],
      },
      {
        id: "bebidas",
        titulo: "Bebidas",
        pergunta: "Equivalências de bebida alcoólica.",
        observacoes: [],
        opcoes: [
          opcao({ id: "bebida-vinho", titulo: "2 taças de vinho", tags: ["vinho", "alcool"] }),
          opcao({ id: "bebida-longneck", titulo: "2 long necks", tags: ["cerveja", "alcool"] }),
          opcao({ id: "bebida-drinks", titulo: "2 drinks", tags: ["drink", "alcool"] }),
          opcao({ id: "bebida-aperol", titulo: "2 aperol", tags: ["aperol", "alcool"] }),
        ],
      },
    ],
    lembretes: [
      "Depois de aproveitar a refeição livre, o mais importante é seguir em frente e voltar com naturalidade ao seu plano.",
      "Uma alimentação equilibrada é feita de escolhas conscientes ao longo do tempo — uma refeição fora da rotina não anula o seu progresso.",
    ],
    tags: ["refeicao livre", "livre", "meia refeicao", "sobremesa", "bebida"],
  },

  // ---------------------------------------------------------------- hambúrguer
  {
    id: "hamburguer",
    nome: "Hambúrguer",
    resumo: "Como montar o lanche do jeito que cabe no seu dia.",
    icone: "hamburguer",
    ordem: 2,
    status: "publicado",
    introducao:
      "Compare as montagens antes de pedir. A diferença costuma estar no número de camadas, não no lanche em si.",
    decisoes: [
      {
        id: "montagem",
        titulo: "A montagem do lanche",
        pergunta: "Quantas camadas o lanche tem?",
        observacoes: [],
        opcoes: [
          opcao({ id: "hamburguer-simples", titulo: "Montagem mais simples", nivel: "melhor", tags: ["simples"] }),
          opcao({
            id: "hamburguer-denso",
            titulo: "Combinações mais densas em energia",
            nivel: "ocasional",
            tags: ["duplo", "bacon", "cheddar"],
          }),
        ],
      },
      {
        id: "completa",
        titulo: "Como refeição livre completa",
        pergunta: null,
        observacoes: [],
        opcoes: [
          opcao({
            id: "hamburguer-completa",
            titulo: "Hambúrguer, batata frita pequena e refrigerante zero açúcar",
            tags: ["refeicao livre"],
          }),
        ],
      },
    ],
    lembretes: [],
    tags: ["hamburguer", "lanche", "burger"],
  },

  // ---------------------------------------------------------------- japonesa
  {
    id: "japonesa",
    nome: "Comida japonesa",
    resumo: "Entradas, combinados e o que costuma pesar no rodízio.",
    icone: "japonesa",
    ordem: 3,
    status: "publicado",
    introducao:
      "Comece pelas entradas, escolha o combinado e deixe as preparações fritas e os molhos cremosos como parte menor da refeição.",
    decisoes: [
      {
        id: "entradas",
        titulo: "Entradas",
        pergunta: "Por onde começar?",
        observacoes: [],
        opcoes: [
          opcao({ id: "sunomono", titulo: "Sunomono", nivel: "melhor", tags: ["sunomono", "pepino"] }),
          opcao({ id: "missoshiro", titulo: "Missoshiro", nivel: "melhor", tags: ["missoshiro", "sopa", "miso"] }),
          opcao({ id: "edamame", titulo: "Edamame", nivel: "melhor", tags: ["edamame", "soja"] }),
        ],
      },
      {
        id: "principal",
        titulo: "Combinados",
        pergunta: "O que pedir depois das entradas?",
        observacoes: [
          "Sugestão de 20 peças.",
          "Peças simples, sem molho.",
          "Molho shoyu tradicional ou light.",
          "O salmão é um peixe muito saudável, mas é rico em gordura, o que eleva o valor calórico da refeição. Para reduzir, prefira atum, peixe branco ou camarão.",
        ],
        opcoes: [
          opcao({ id: "sashimi", titulo: "Sashimi", nivel: "melhor", tags: ["sashimi", "peixe"] }),
          opcao({ id: "niguiri", titulo: "Niguiri", nivel: "boa", tags: ["niguiri", "sushi"] }),
          opcao({
            id: "temaki-simples",
            titulo: "Temaki simples, sem cream cheese",
            descricao: "Conta como meia refeição livre.",
            nivel: "boa",
            tags: ["temaki"],
          }),
        ],
      },
      {
        id: "ocasionais",
        titulo: "Preparações fritas e molhos cremosos",
        pergunta: "E os itens que aparecem no rodízio?",
        observacoes: [],
        opcoes: [
          opcao({ id: "fritos", titulo: "Preparações fritas", nivel: "ocasional", tags: ["frito", "tempura", "hot"] }),
          opcao({ id: "molhos-cremosos", titulo: "Molhos cremosos", nivel: "ocasional", tags: ["molho", "cremoso"] }),
        ],
      },
    ],
    lembretes: [],
    tags: ["japonesa", "japones", "sushi", "sashimi", "rodizio", "temaki"],
  },

  // ---------------------------------------------------------------- massas
  {
    id: "massas",
    nome: "Massas",
    resumo: "Quantidade da massa, proteína e molho.",
    icone: "massas",
    ordem: 4,
    status: "publicado",
    introducao: "Três escolhas definem o prato: quanto de massa, se entra proteína e qual molho acompanha.",
    decisoes: [
      {
        id: "montagens",
        titulo: "Montagens que fecham uma refeição completa",
        pergunta: "Qual delas combina com o lugar onde você está?",
        observacoes: [
          "Prefira o molho ao sugo.",
          "Adicione proteína para trazer mais saciedade: massa e frango, massa e camarão, massa e carne magra.",
          "Boa opção de restaurante: Spoleto.",
        ],
        opcoes: [
          opcao({
            id: "massa-camarao",
            titulo: "Massa (200 g) com camarão (120 g), ricota temperada e molho pesto",
            tags: ["camarao", "pesto", "ricota"],
          }),
          opcao({
            id: "massa-frango",
            titulo: "Massa (100 g) com frango, legumes e molho pomodoro",
            tags: ["frango", "pomodoro", "legumes"],
          }),
          opcao({ id: "massa-lasanha", titulo: "Lasanha bolonhesa", tags: ["lasanha", "bolonhesa"] }),
        ],
      },
    ],
    lembretes: [],
    tags: ["massa", "macarrao", "italiano", "molho", "spoleto", "lasanha"],
  },

  // ---------------------------------------------------------------- pizza
  {
    id: "pizza",
    nome: "Pizza",
    resumo: "Quantas fatias fecham uma refeição, por tipo de massa.",
    icone: "pizza",
    ordem: 5,
    status: "publicado",
    introducao: "A conta muda com a massa: quanto mais densa, menos fatias fecham a mesma refeição.",
    decisoes: [
      {
        id: "fatias",
        titulo: "Quantas fatias",
        pergunta: "Qual é a massa da pizzaria?",
        observacoes: [
          "Prefira opções com proteína e sem muita adição de queijo, como frango ou carne seca.",
        ],
        opcoes: [
          opcao({ id: "pizza-fina", titulo: "3 fatias de massa fina", tags: ["massa fina"] }),
          opcao({
            id: "pizza-grossa",
            titulo: "2 fatias de massa grossa ou de borda recheada",
            tags: ["massa grossa", "borda recheada"],
          }),
        ],
      },
    ],
    lembretes: [],
    tags: ["pizza", "pizzaria", "fatia", "borda"],
  },

  // ---------------------------------------------------------------- açaí
  {
    id: "acai",
    nome: "Açaí",
    resumo: "Tamanho da tigela e o que entra junto.",
    icone: "acai",
    ordem: 6,
    status: "publicado",
    introducao: "O tamanho decide se o açaí é a refeição livre inteira ou metade dela.",
    decisoes: [
      {
        id: "tamanho",
        titulo: "O tamanho da tigela",
        pergunta: "Quanto vem no copo?",
        observacoes: [],
        opcoes: [
          opcao({
            id: "acai-500",
            titulo: "500 ml com banana e leite condensado",
            descricao: "Fecha uma refeição livre completa.",
            tags: ["completa"],
          }),
          opcao({
            id: "acai-300",
            titulo: "300 ml com 1 fruta e leite condensado",
            descricao: "Conta como meia refeição livre.",
            tags: ["meia"],
          }),
        ],
      },
    ],
    lembretes: [],
    tags: ["acai", "tigela", "copo"],
  },

  // ---------------------------------------------------------------- doces
  {
    id: "doces",
    nome: "Doces e sobremesas",
    resumo: "Cada uma destas conta como meia refeição livre.",
    icone: "doces",
    ordem: 7,
    status: "publicado",
    introducao: "Duas destas opções somam uma refeição livre completa.",
    decisoes: [
      {
        id: "sobremesas",
        titulo: "Meias refeições doces",
        pergunta: "O que está na mesa?",
        observacoes: [],
        opcoes: [
          opcao({
            id: "doce-gelato",
            titulo: "Gelato: 1 copo médio com 2 sabores",
            descricao: "Bacio di Latte, Lullo, Mi Garba.",
            tags: ["gelato", "sorvete"],
          }),
          opcao({
            id: "doce-cookie",
            titulo: "1 cookie artesanal grande, estilo americano",
            descricao: "Mr. Cheney, American Day.",
            tags: ["cookie"],
          }),
          opcao({ id: "doce-bolo", titulo: "1 fatia média de bolo ou torta com calda", tags: ["bolo", "torta"] }),
          opcao({ id: "doce-brownie", titulo: "1 brownie com 1 bola de sorvete", tags: ["brownie", "sorvete"] }),
          opcao({
            id: "doce-milkshake",
            titulo: "Milkshake pequeno",
            descricao: "Bob's, McDonald's.",
            kcal: 330,
            mostrarKcal: false,
            tags: ["milkshake"],
          }),
          opcao({ id: "doce-acai", titulo: "Açaí de 300 ml com 1 fruta e leite condensado", tags: ["acai"] }),
        ],
      },
    ],
    lembretes: [],
    tags: ["doce", "sobremesa", "chocolate", "bolo", "sorvete", "cookie"],
  },

  // Categorias já reservadas — aparecem na grade e na busca, ainda sem conteúdo.
  { id: "subway", nome: "Subway", resumo: null, icone: "sanduiche", ordem: 8, status: "em-preparacao", introducao: null, decisoes: [], lembretes: [], tags: ["subway", "sanduiche", "sub"] },
  { id: "restaurantes", nome: "Restaurantes", resumo: null, icone: "restaurante", ordem: 9, status: "em-preparacao", introducao: null, decisoes: [], lembretes: [], tags: ["restaurante", "self service", "buffet", "por quilo"] },
  { id: "delivery", nome: "Delivery", resumo: null, icone: "delivery", ordem: 10, status: "em-preparacao", introducao: null, decisoes: [], lembretes: [], tags: ["delivery", "ifood", "entrega"] },
];

export const CATEGORIA_COMER_FORA_POR_ID: ReadonlyMap<string, CategoriaComerFora> = new Map(
  CATEGORIAS_COMER_FORA.map((c) => [c.id, c]),
);
