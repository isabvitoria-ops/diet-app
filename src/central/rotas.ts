/**
 * Rotas da Central (§19). Ficam num só lugar para que nenhum componente
 * escreva caminho na mão — e para que mudar o prefixo (hoje `/central`) seja
 * uma linha só, caso um dia a Central vire a tela inicial do app.
 */
export const BASE = "/central";

export const rotas = {
  home: BASE,
  trocas: `${BASE}/trocas`,
  /** Abre a calculadora já com o alimento escolhido. */
  trocaCom: (alimentoId: string) => `${BASE}/trocas?de=${encodeURIComponent(alimentoId)}`,
  substituicoes: `${BASE}/substituicoes`,
  grupo: (grupoId: string) => `${BASE}/substituicoes/${grupoId}`,
  comerFora: `${BASE}/comer-fora`,
  categoria: (categoriaId: string) => `${BASE}/comer-fora/${categoriaId}`,
  opcao: (categoriaId: string, opcaoId: string) =>
    `${BASE}/comer-fora/${categoriaId}?opcao=${encodeURIComponent(opcaoId)}`,
  guias: `${BASE}/guias`,
  guia: (guiaId: string) => `${BASE}/guias/${guiaId}`,
  salvos: `${BASE}/salvos`,
  busca: (consulta?: string) =>
    consulta ? `${BASE}/busca?q=${encodeURIComponent(consulta)}` : `${BASE}/busca`,
};
