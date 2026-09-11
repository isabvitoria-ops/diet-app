import type { Medida, MedidaDoAlimento } from "./unidade";

/**
 * Atributos que ligam/desligam os filtros da calculadora (§6).
 *
 * `null` é diferente de `false`: quer dizer "a nutricionista ainda não
 * informou". Um alimento com `semGluten: null` não é apresentado como
 * contendo glúten — ele simplesmente não entra quando o filtro está ligado,
 * e a tela avisa que o dado está pendente em vez de chutar.
 */
export interface AtributosAlimento {
  semGluten: boolean | null;
  semLactose: boolean | null;
}

export interface Alimento {
  id: string;
  nome: string;
  grupoId: string;
  /** Unidade em que as medidas deste alimento são convertidas (normalmente "g" ou "ml"). */
  unidadeBaseId: string;
  /**
   * Porção de referência do material de substituição (§8): 1 porção de arroz
   * cozido = 100 g. É a partir dela que o sistema deriva trocas dentro do
   * mesmo grupo sem precisar de uma linha de equivalência por par.
   * `null` = ainda não cadastrada; o alimento aparece na lista, mas não é
   * oferecido na calculadora.
   */
  porcao: Medida | null;
  medidas: MedidaDoAlimento[];
  atributos: AtributosAlimento;
  /** Palavras que a busca global também aceita ("massa", "espaguete"). */
  tags: string[];
  imagem: string | null;
  observacao: string | null;
}

/**
 * Regra de consumo de um grupo inteiro.
 *
 * "porcoes" é o caso comum (carboidratos, proteínas...): o grupo trabalha em
 * porções e trocas internas saem da razão entre elas. "livre" é o caso dos
 * vegetais livres (§12): quantidade livre, com um mínimo por refeição.
 */
export type RegraGrupo =
  | { tipo: "porcoes" }
  | {
      tipo: "livre";
      minimos: { refeicao: string; medida: Medida }[];
      texto: string;
    };

export interface GrupoAlimentar {
  id: string;
  nome: string;
  descricao: string | null;
  ordem: number;
  regra: RegraGrupo | null;
  /**
   * Se trocas dentro do grupo podem ser derivadas porção↔porção. Desligue
   * num grupo em que isso não valha e o sistema passa a exigir equivalência
   * explícita ali — sem mexer em código (§10).
   */
  trocaPorPorcao: boolean;
  tags: string[];
}
