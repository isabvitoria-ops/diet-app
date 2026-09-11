import type { NivelEscolha } from "@/central/types";

/**
 * Classificação das escolhas (§15).
 *
 * A linguagem é de contexto, não de permissão: "melhor escolha", "boa
 * opção", "mais ocasional". Em nenhum lugar aparece "pode"/"não pode" nem
 * "bom"/"ruim" — a ideia é ensinar a decidir, não autorizar.
 */
const ROTULOS: Record<NivelEscolha, string> = {
  melhor: "Melhor escolha",
  boa: "Boa opção",
  ocasional: "Mais ocasional",
};

export function Selo({ nivel }: { nivel: NivelEscolha }) {
  return <span className={`c-selo ${nivel}`}>{ROTULOS[nivel]}</span>;
}

export function SeloNeutro({ children }: { children: React.ReactNode }) {
  return <span className="c-selo neutro">{children}</span>;
}
