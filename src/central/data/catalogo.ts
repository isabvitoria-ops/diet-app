import type { Alimento, CategoriaComerFora, Equivalencia, GrupoAlimentar, Guia, Unidade } from "@/central/types";
import { UNIDADES, UNIDADE_POR_ID } from "./unidades";
import { GRUPOS, GRUPO_POR_ID } from "./grupos";
import { ALIMENTOS, ALIMENTO_POR_ID } from "./alimentos";
import { EQUIVALENCIAS } from "./equivalencias";
import { CATEGORIAS_COMER_FORA, CATEGORIA_COMER_FORA_POR_ID } from "./comerFora";
import { GUIAS, GUIA_POR_ID } from "./guias";

/**
 * Fachada de leitura do catálogo — a única porta por onde as telas chegam
 * aos dados.
 *
 * É aqui que a migração para Supabase/Firebase acontece (§30): as telas não
 * importam `ALIMENTOS` nem `EQUIVALENCIAS` diretamente, elas chamam
 * `catalogo.alimento(id)`. No dia da migração, estas funções passam a
 * devolver `Promise` e só os hooks precisam mudar — nenhum componente
 * conhece a origem do dado.
 */
export const catalogo = {
  unidades(): Unidade[] {
    return UNIDADES;
  },
  unidade(id: string): Unidade | null {
    return UNIDADE_POR_ID.get(id) ?? null;
  },

  grupos(): GrupoAlimentar[] {
    return [...GRUPOS].sort((a, b) => a.ordem - b.ordem);
  },
  grupo(id: string): GrupoAlimentar | null {
    return GRUPO_POR_ID.get(id) ?? null;
  },

  alimentos(): Alimento[] {
    return ALIMENTOS;
  },
  alimento(id: string): Alimento | null {
    return ALIMENTO_POR_ID.get(id) ?? null;
  },
  alimentosDoGrupo(grupoId: string): Alimento[] {
    return ALIMENTOS.filter((a) => a.grupoId === grupoId).sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR"));
  },

  equivalencias(): Equivalencia[] {
    return EQUIVALENCIAS;
  },
  /** Todas as equivalências que tocam este alimento, nos dois sentidos. */
  equivalenciasDe(alimentoId: string): Equivalencia[] {
    return EQUIVALENCIAS.filter(
      (e) =>
        e.origemAlimentoId === alimentoId || (e.bidirecional && e.destinoAlimentoId === alimentoId),
    );
  },

  categoriasComerFora(): CategoriaComerFora[] {
    return [...CATEGORIAS_COMER_FORA].sort((a, b) => a.ordem - b.ordem);
  },
  categoriaComerFora(id: string): CategoriaComerFora | null {
    return CATEGORIA_COMER_FORA_POR_ID.get(id) ?? null;
  },

  guias(): Guia[] {
    return [...GUIAS].sort((a, b) => a.ordem - b.ordem);
  },
  guia(id: string): Guia | null {
    return GUIA_POR_ID.get(id) ?? null;
  },
};
