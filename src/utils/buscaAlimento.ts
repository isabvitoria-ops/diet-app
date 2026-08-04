import type { Alimento, GrupoAlimento } from "@/types";

function semAcento(s: string): string {
  return s.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
}

function tokens(s: string): string[] {
  return semAcento(s)
    .replace(/[^a-z0-9\s]/g, " ")
    .split(/\s+/)
    .filter((t) => t.length > 2);
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
