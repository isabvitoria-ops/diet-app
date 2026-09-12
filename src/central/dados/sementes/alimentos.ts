import type { Alimento } from "@/central/types";

/**
 * Cadastro de alimentos.
 *
 * REGRA DO BRIEFING (§8 e §29): nenhum valor aqui foi estimado. Só entra
 * número que veio do material da nutricionista — ou que é aritmética direta
 * sobre um número dela (o caso do macarrão, explicado na `observacao` do
 * próprio item). Alimento sem porção cadastrada fica com `porcao: null`:
 * ele aparece na lista de Substituições marcado como pendente e **não** é
 * oferecido na calculadora, em vez de ganhar um valor plausível inventado.
 *
 * COMO ACRESCENTAR UM ALIMENTO
 * ----------------------------
 * Some uma chamada de `alimento({...})` na lista abaixo:
 *
 *   alimento({
 *     id: "batata-doce-cozida",          // minúsculas, sem acento, com hífen
 *     nome: "Batata-doce cozida",
 *     grupoId: "carboidratos",           // ver data/grupos.ts
 *     porcao: { quantidade: 120, unidadeId: "g" },
 *     semGluten: true,
 *     tags: ["batata", "tuberculo"],
 *   })
 *
 * Feito isso, o alimento já entra na busca global, na lista do grupo e —
 * por ter porção — em todas as trocas dentro do grupo, sem escrever
 * nenhuma equivalência par a par.
 */

interface Entrada {
  id: string;
  nome: string;
  grupoId: string;
  porcao?: Alimento["porcao"];
  unidadeBaseId?: string;
  medidas?: Alimento["medidas"];
  semGluten?: boolean | null;
  semLactose?: boolean | null;
  tags?: string[];
  observacao?: string | null;
}

/** Preenche os campos opcionais para que cadastrar um alimento seja curto. */
function alimento(e: Entrada): Alimento {
  return {
    id: e.id,
    nome: e.nome,
    grupoId: e.grupoId,
    unidadeBaseId: e.unidadeBaseId ?? "g",
    porcao: e.porcao ?? null,
    medidas: e.medidas ?? [],
    atributos: {
      semGluten: e.semGluten ?? null,
      semLactose: e.semLactose ?? null,
    },
    tags: e.tags ?? [],
    imagem: null,
    observacao: e.observacao ?? null,
    ativo: true,
  };
}

export const ALIMENTOS: Alimento[] = [
  // ---------------------------------------------------------------- carboidratos
  alimento({
    id: "arroz-cozido",
    nome: "Arroz integral ou branco cozido",
    grupoId: "carboidratos",
    // §8 do briefing: "uma porção de arroz corresponde a 100 g".
    porcao: { quantidade: 100, unidadeId: "g" },
    semGluten: true,
    semLactose: true,
    tags: ["arroz", "integral", "branco", "cozido"],
  }),
  alimento({
    id: "macarrao-cozido",
    nome: "Macarrão cozido",
    grupoId: "carboidratos",
    // Não é estimativa: a equivalência cadastrada diz que 100 g de arroz
    // (= 1 porção, §8) equivalem a 80 g de macarrão — logo 1 porção de
    // macarrão são 80 g. Se a lista de substituição trouxer outro valor,
    // corrija aqui e em data/equivalencias.ts.
    porcao: { quantidade: 80, unidadeId: "g" },
    semGluten: false,
    semLactose: true,
    tags: ["macarrao", "massa", "espaguete", "penne"],
    observacao: "Porção derivada da equivalência 100 g de arroz = 80 g de macarrão.",
  }),
  alimento({
    id: "abobora-cozida",
    nome: "Abóbora cozida",
    grupoId: "carboidratos",
    semGluten: true,
    semLactose: true,
    tags: ["abobora", "jerimum"],
  }),
  alimento({
    id: "batata-cozida",
    nome: "Batata cozida",
    grupoId: "carboidratos",
    semGluten: true,
    semLactose: true,
    tags: ["batata", "tuberculo"],
  }),
  alimento({
    id: "pao",
    nome: "Pão",
    grupoId: "carboidratos",
    tags: ["pao", "frances", "forma"],
  }),
  alimento({
    id: "tapioca",
    nome: "Tapioca",
    grupoId: "carboidratos",
    semGluten: true,
    semLactose: true,
    tags: ["tapioca", "goma"],
  }),

  // ---------------------------------------------------------------- vegetais livres
  // §12: a lista de itens veio do material; a quantidade é livre, então
  // nenhum deles tem porção — a regra do grupo (mínimo de 150 g no almoço e
  // no jantar) vive em data/grupos.ts.
  ...[
    ["abobrinha", "Abobrinha"],
    ["aspargos", "Aspargos"],
    ["alho", "Alho"],
    ["alho-poro", "Alho-poró"],
    ["berinjela", "Berinjela"],
    ["beterraba", "Beterraba"],
    ["brocolis", "Brócolis"],
    ["cebola", "Cebola"],
    ["cenoura", "Cenoura"],
    ["chuchu", "Chuchu"],
    ["cogumelos", "Cogumelos"],
    ["couve-flor", "Couve-flor"],
    ["couve-de-bruxelas", "Couve-de-bruxelas"],
    ["ervilha-torta", "Ervilha-torta"],
    ["jilo", "Jiló"],
    ["maxixe", "Maxixe"],
    ["nabo", "Nabo"],
    ["palmito", "Palmito"],
    ["pimentao", "Pimentão"],
    ["pepino", "Pepino"],
    ["repolho", "Repolho"],
    ["quiabo", "Quiabo"],
    ["rabanete", "Rabanete"],
    ["tomate", "Tomate"],
    ["tomatinho", "Tomatinho"],
    ["vagem", "Vagem"],
    ["folhas-e-brotos", "Folhas e brotos"],
  ].map(([id, nome]) =>
    alimento({
      id: id as string,
      nome: nome as string,
      grupoId: "vegetais-livres",
      semGluten: true,
      semLactose: true,
      tags: ["vegetal", "legume", "livre"],
    }),
  ),

  // ---------------------------------------------------------------- demais grupos
  // Proteínas, gorduras, frutas e outros ainda não têm itens cadastrados.
  // As telas já lidam com grupo vazio; some as linhas quando os valores
  // da lista de substituição estiverem em mãos.
];

export const ALIMENTO_POR_ID: ReadonlyMap<string, Alimento> = new Map(ALIMENTOS.map((a) => [a.id, a]));
