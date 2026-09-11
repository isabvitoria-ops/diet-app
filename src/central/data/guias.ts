import type { Guia } from "@/central/types";

/**
 * Guias (§17).
 *
 * Os temas abaixo foram reservados pela nutricionista; o conteúdo clínico é
 * dela e entra depois — o briefing pede explicitamente para não inventar
 * nada aqui. Enquanto `secoes` estiver vazio, a tela do guia mostra um
 * estado de "em preparação" em vez de texto de enchimento.
 *
 * COMO PUBLICAR UM GUIA
 * ---------------------
 *   {
 *     id: "refeicao-livre",
 *     titulo: "Refeição livre",
 *     tema: "No dia a dia",
 *     resumo: "Uma linha que aparece na listagem.",
 *     ordem: 1,
 *     status: "publicado",
 *     secoes: [
 *       {
 *         id: "como-funciona",
 *         titulo: "Como funciona",
 *         paragrafos: ["Texto corrido, um parágrafo por item."],
 *         itens: ["Marcador curto", "Outro marcador"],
 *       },
 *     ],
 *     tags: ["refeicao livre"],
 *   }
 */
function guia(id: string, titulo: string, tema: string, ordem: number, tags: string[]): Guia {
  return { id, titulo, tema, resumo: null, ordem, status: "em-preparacao", secoes: [], tags };
}

export const GUIAS: Guia[] = [
  guia("refeicao-livre", "Refeição livre", "No dia a dia", 1, ["refeicao livre", "flexibilidade"]),
  guia("comer-fora", "Comer fora", "No dia a dia", 2, ["comer fora", "restaurante"]),
  guia("industrializados", "Industrializados", "No dia a dia", 3, ["industrializado", "rotulo", "ultraprocessado"]),
  guia("doces", "Doces", "No dia a dia", 4, ["doce", "sobremesa", "acucar"]),
  guia("alcool", "Álcool", "No dia a dia", 5, ["alcool", "bebida", "cerveja", "vinho"]),
  guia("constipacao", "Constipação", "Digestão", 6, ["constipacao", "intestino preso", "fibra"]),
  guia("gases", "Gases", "Digestão", 7, ["gases", "flatulencia"]),
  guia("distensao-abdominal", "Distensão abdominal", "Digestão", 8, ["distensao", "inchaco", "barriga"]),
  guia("diarreia", "Diarreia", "Digestão", 9, ["diarreia", "intestino solto"]),
  guia("lactose", "Lactose", "Restrições", 10, ["lactose", "leite", "laticinio"]),
  guia("fodmap", "FODMAP", "Restrições", 11, ["fodmap", "sii", "intestino irritavel"]),
];

export const GUIA_POR_ID: ReadonlyMap<string, Guia> = new Map(GUIAS.map((g) => [g.id, g]));

/** Ordem em que os blocos de tema aparecem na listagem. */
export const TEMAS_GUIAS = ["No dia a dia", "Digestão", "Restrições"] as const;
