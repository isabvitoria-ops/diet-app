import { useNavigate } from "react-router-dom";
import { catalogo } from "@/central/dados/catalogo";
import { CabecalhoPagina } from "@/central/components/CabecalhoPagina";
import { Icone } from "@/central/components/Icone";
import { rotas } from "@/central/rotas";

/**
 * Comer fora (§13) — a grade de categorias.
 *
 * As categorias que ainda não têm conteúdo continuam na grade, marcadas como
 * "em breve": o paciente vê o que está por vir e a nutricionista tem a lista
 * do que falta escrever. Some uma categoria em `data/comerFora.ts` e ela
 * aparece aqui e na busca global, sem mexer nesta tela.
 */
export function ComerFora() {
  const navegar = useNavigate();
  const categorias = catalogo.categoriasComerFora();
  const prontas = categorias.filter((c) => c.status === "publicado");
  const emBreve = categorias.filter((c) => c.status !== "publicado");

  return (
    <>
      <CabecalhoPagina
        titulo="Comer fora"
        descricao="Veja estratégias para escolher melhor fora de casa."
        voltarPara={rotas.home}
      />

      <div className="c-conteudo">
        <section className="c-secao">
          <div className="c-grade">
            {prontas.map((categoria) => (
              <button
                key={categoria.id}
                type="button"
                className="c-categoria"
                onClick={() => navegar(rotas.categoria(categoria.id))}
              >
                <span className="c-categoria-icone">
                  <Icone nome={categoria.icone} tamanho={21} />
                </span>
                <span>
                  <h3>{categoria.nome}</h3>
                  {categoria.resumo && <p>{categoria.resumo}</p>}
                </span>
              </button>
            ))}
          </div>
        </section>

        {emBreve.length > 0 && (
          <section className="c-secao">
            <h2 className="c-secao-titulo">Em breve</h2>
            <div className="c-grade">
              {emBreve.map((categoria) => (
                <button
                  key={categoria.id}
                  type="button"
                  className="c-categoria pendente"
                  onClick={() => navegar(rotas.categoria(categoria.id))}
                >
                  <span className="c-categoria-icone">
                    <Icone nome={categoria.icone} tamanho={21} />
                  </span>
                  <span>
                    <h3>{categoria.nome}</h3>
                    <p>Em preparação</p>
                  </span>
                </button>
              ))}
            </div>
          </section>
        )}
      </div>
    </>
  );
}
