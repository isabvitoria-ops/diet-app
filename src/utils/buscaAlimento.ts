import type { Alimento, GrupoAlimento } from "@/types";

function semAcento(s: string): string {
  return s.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
}

/**
 * Grafias do dia a dia que não batem com o nome da TACO. A nutricionista
 * escreve "mussarela" (a forma corrente) e a base registra "mozarela" — sem
 * isto a busca devolvia zero sugestões e o item ficava impossível de
 * vincular pela tela, travando a publicação do plano inteiro.
 */
const SINONIMOS: Record<string, string> = {
  mussarela: "mozarela",
  muzzarela: "mozarela",
  mozzarella: "mozarela",
  mucarela: "mozarela",
  iogurte: "iogurte",
  aipim: "mandioca",
  macaxeira: "mandioca",
  tangerina: "mexerica",
  bergamota: "mexerica",
};

function tokens(s: string): string[] {
  return semAcento(s)
    .replace(/[^a-z0-9\s]/g, " ")
    .split(/\s+/)
    .filter((t) => t.length > 2)
    .map((t) => SINONIMOS[t] ?? t);
}

export interface ResultadoBusca {
  pontos: number;
  alimento: Alimento;
}

/**
 * Busca por sobreposição de palavras — aguenta "arroz branco cozido" virar
 * "Arroz, tipo 1, cozido". Portada literalmente do protótipo do painel
 * (função `buscar`), só parametrizada para receber a base em vez de usar
 * uma constante global.
 */
export function buscarAlimentos(
  base: Alimento[],
  consulta: string,
  limite = 8,
  grupo: GrupoAlimento | null = null,
): ResultadoBusca[] {
  const tq = tokens(consulta);
  if (!tq.length) return [];
  return base
    .filter((a) => !grupo || a.grupo === grupo)
    .map((a) => {
      const tn = tokens(a.nome);
      let pontos = 0;
      tq.forEach((t) => {
        if (tn.includes(t)) pontos += 2;
        else if (tn.some((x) => x.startsWith(t) || t.startsWith(x))) pontos += 1;
      });
      return { alimento: a, pontos: pontos - Math.abs(tn.length - tq.length) * 0.15 };
    })
    .filter((x) => x.pontos > 0)
    .sort((a, b) => b.pontos - a.pontos)
    .slice(0, limite);
}

export function tokensDe(s: string): string[] {
  return tokens(s);
}

/** Equivalência calculada — ferramenta de apoio só para a nutricionista (regra #3). */
export function equivalenteNutriente(
  de: Alimento,
  gramasDe: number,
  para: Alimento,
  nutriente: keyof Alimento,
): number | null {
  const a = de[nutriente] as number;
  const b = para[nutriente] as number;
  if (!a || !b) return null;
  return (gramasDe * a) / b;
}
