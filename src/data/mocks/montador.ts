import type { ItemMontador } from "@/types";
import { COD } from "./fichasAlimento";

/**
 * Catálogo do "Montar uma refeição" de Marina, portado do protótipo
 * (constante `POOL`). `quantidadeBase` é a porção cheia quando o alimento
 * vem sozinho no grupo — a divisão entre irmãos do mesmo grupo acontece em
 * hooks/useMontador, não aqui.
 */
export const MONTADOR_POOL_MARINA: ItemMontador[] = [
  { alimentoCodigoTaco: COD.arroz, grupo: "carb", quantidadeBase: { valor: 4, unidade: "colheres de sopa" } },
  { alimentoCodigoTaco: COD.batata, grupo: "carb", quantidadeBase: { valor: 2, unidade: "unidades pequenas" } },
  { alimentoCodigoTaco: COD.aveia, grupo: "carb", quantidadeBase: { valor: 3, unidade: "colheres de sopa" } },
  {
    alimentoCodigoTaco: COD.pao,
    grupo: "carb",
    quantidadeBase: { valor: 1, unidade: "unidade" },
    aviso: "Fermenta mais que as outras opções desta fase.",
  },
  { alimentoCodigoTaco: COD.frango, grupo: "prot", quantidadeBase: { valor: 1, unidade: "filé médio" } },
  { alimentoCodigoTaco: COD.ovo, grupo: "prot", quantidadeBase: { valor: 2, unidade: "unidades" } },
  {
    alimentoCodigoTaco: COD.feijao,
    grupo: "legum",
    quantidadeBase: { valor: 1, unidade: "concha rasa" },
    aviso: "Uma concha rasa é o limite desta fase.",
  },
  { alimentoCodigoTaco: COD.banana, grupo: "fruta", quantidadeBase: { valor: 1, unidade: "unidade média" } },
  { alimentoCodigoTaco: COD.maca, grupo: "fruta", bloqueado: "Fora do cardápio na fase 1. Volta na reintrodução." },
  { alimentoCodigoTaco: COD.leite, grupo: "prot", bloqueado: "Contém lactose. Fora nesta fase." },
  { alimentoCodigoTaco: COD.abobrinha, grupo: "vegetal", livre: true },
  { alimentoCodigoTaco: COD.cenoura, grupo: "vegetal", livre: true },
  { alimentoCodigoTaco: COD.azeite, grupo: "gordura", quantidadeBase: { valor: 1, unidade: "colher de sopa" } },
];
