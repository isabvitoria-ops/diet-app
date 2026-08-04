import type { DestinoPost, PostFeed, TipoPost } from "@/types";
import { feedRepository } from "@/repositories";

export async function listarFeed(): Promise<{ post: PostFeed; curtidas: number }[]> {
  const posts = await feedRepository.listarPosts();
  const comCurtidas = await Promise.all(
    posts.map(async (post) => ({ post, curtidas: await feedRepository.contarCurtidas(post.id) })),
  );
  return comCurtidas;
}

export async function alternarCurtida(postId: string, pacienteId: string): Promise<number> {
  return feedRepository.alternarCurtida(postId, pacienteId);
}

/** Regra §13: só a nutricionista publica; garantido aqui pela assinatura (sem `pacienteId` autor). */
export async function publicarPost(
  nutricionistaId: string,
  tipo: TipoPost,
  titulo: string,
  texto: string,
  destino: DestinoPost,
  corId: string,
): Promise<PostFeed> {
  if (!titulo.trim()) throw new Error("Título é obrigatório.");
  return feedRepository.publicarPost(nutricionistaId, tipo, titulo, texto, destino, corId);
}
