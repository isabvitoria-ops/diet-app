import { create } from "zustand";
import type { Favorito, TipoFavorito } from "@/central/types";
import { armazenamentoLocal } from "@/central/utils/armazenamento";

const armazenamento = armazenamentoLocal<Favorito>("central:favoritos:v1");

/** Chave estável: salvar duas vezes o mesmo item alterna, não duplica. */
export function idFavorito(tipo: TipoFavorito, refId: string): string {
  return `${tipo}:${refId}`;
}

export type NovoFavorito = Omit<Favorito, "id" | "salvoEm">;

interface EstadoFavoritos {
  itens: Favorito[];
  alternar(novo: NovoFavorito): boolean;
  remover(id: string): void;
  limpar(): void;
}

export const useFavoritos = create<EstadoFavoritos>((set, get) => ({
  itens: armazenamento.ler(),

  alternar(novo) {
    const id = idFavorito(novo.tipo, novo.refId);
    const existentes = get().itens;
    const jaSalvo = existentes.some((f) => f.id === id);
    const itens = jaSalvo
      ? existentes.filter((f) => f.id !== id)
      : [{ ...novo, id, salvoEm: new Date().toISOString() }, ...existentes];
    armazenamento.escrever(itens);
    set({ itens });
    return !jaSalvo;
  },

  remover(id) {
    const itens = get().itens.filter((f) => f.id !== id);
    armazenamento.escrever(itens);
    set({ itens });
  },

  limpar() {
    armazenamento.escrever([]);
    set({ itens: [] });
  },
}));

/** Assina só o "está salvo?" deste item — não redesenha a tela a cada favorito alheio. */
export function useEstaSalvo(tipo: TipoFavorito, refId: string): boolean {
  const id = idFavorito(tipo, refId);
  return useFavoritos((estado) => estado.itens.some((f) => f.id === id));
}
