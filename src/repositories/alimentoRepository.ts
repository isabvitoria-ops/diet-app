import type { Alimento, FichaEducativaAlimento, GrupoAlimento, ItemMontador } from "@/types";
import { TACO, alimentoPorCodigo } from "@/data/taco";
import { buscarAlimentos, type ResultadoBusca } from "@/utils/buscaAlimento";
import { atraso, db } from "./mockDb";

/**
 * A base TACO inteira é uso interno (regra #2) — este repository é
 * importado só por código do painel da nutricionista. As telas do paciente
 * nunca devem importar `@/data/taco` nem este arquivo diretamente; elas
 * recebem alimentos já resolvidos (nome + quantidade) via `planoService`.
 */
export async function buscar(consulta: string, limite = 8, grupo: GrupoAlimento | null = null): Promise<ResultadoBusca[]> {
  await atraso(120);
  return buscarAlimentos(TACO, consulta, limite, grupo);
}

export async function listarPorGrupo(grupo: GrupoAlimento, limite = 200): Promise<Alimento[]> {
  await atraso();
  return TACO.filter((a) => a.grupo === grupo).slice(0, limite);
}

export async function porCodigo(codigo: number): Promise<Alimento | null> {
  await atraso();
  return alimentoPorCodigo(codigo) ?? null;
}

export async function contarTotal(): Promise<number> {
  return TACO.length;
}

export async function buscarFicha(codigo: number): Promise<FichaEducativaAlimento | null> {
  await atraso();
  return db.fichasAlimento.find((f) => f.alimentoCodigoTaco === codigo) ?? null;
}

export async function buscarPoolMontador(pacienteId: string): Promise<ItemMontador[]> {
  await atraso();
  return db.montadorPools[pacienteId] ?? [];
}
