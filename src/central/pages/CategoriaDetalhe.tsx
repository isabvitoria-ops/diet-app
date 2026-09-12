import { useState } from "react";
import { useParams, useSearchParams } from "react-router-dom";
import type { NivelEscolha } from "@/central/types";
import { catalogo } from "@/central/dados/catalogo";
import { CabecalhoPagina } from "@/central/components/CabecalhoPagina";
import { CartaoOpcao } from "@/central/components/CartaoOpcao";
import { EstadoVazio } from "@/central/components/EstadoVazio";
import { BotaoFavorito } from "@/central/components/BotaoFavorito";
import { rotas } from "@/central/rotas";

/**
 * Uma categoria de "Comer fora" por dentro.
 *
 * A tela é organizada pelas decisões que a refeição realmente exige — no
 * material de massas, por exemplo, a quantidade da massa, a proteína e o
 * molho são três escolhas separadas. O filtro no topo serve para quem chegou
 * com a pergunta pronta ("o que é melhor escolha aqui?").
 */
const FILTROS: { valor: NivelEscolha | "todos"; rotulo: string }[] = [
  { valor: "todos", rotulo: "Todas" },
  { valor: "melhor", rotulo: "Melhor escolha" },
  { valor: "boa", rotulo: "Boa opção" },
  { valor: "ocasional", rotulo: "Mais ocasional" },
];

export function CategoriaDetalhe() {
  const { categoriaId = "" } = useParams();
  const [parametros] = useSearchParams();
  const [filtro, definirFiltro] = useState<NivelEscolha | "todos">("todos");

  const categoria = catalogo.categoriaComerFora(categoriaId);
  const opcaoDestacada = parametros.get("opcao");

  if (!categoria) {
    return (
      <>
        <CabecalhoPagina titulo="Categoria não encontrada" voltarPara={rotas.comerFora} />
        <div className="c-conteudo">
          <EstadoVazio titulo="Esta categoria não existe" descricao="Volte e escolha outra." />
        </div>
      </>
    );
  }

  const totalDeOpcoes = categoria.decisoes.reduce((soma, d) => soma + d.opcoes.length, 0);
  const temNiveis = categoria.decisoes.some((d) => d.opcoes.some((o) => o.nivel !== null));

  return (
    <>
      <CabecalhoPagina
        titulo={categoria.nome}
        descricao={categoria.resumo}
        voltarPara={rotas.comerFora}
        acao={
          <BotaoFavorito
            item={{
              tipo: "categoria",
              refId: categoria.id,
              titulo: categoria.nome,
              subtitulo: "Comer fora",
              rota: rotas.categoria(categoria.id),
            }}
          />
        }
      />

      <div className="c-conteudo">
        {categoria.introducao && <p className="c-intro">{categoria.introducao}</p>}

        {totalDeOpcoes === 0 ? (
          <EstadoVazio
            icone="comerFora"
            titulo="Conteúdo em preparação"
            descricao={
              categoria.decisoes.length > 0
                ? "As escolhas desta refeição já estão mapeadas. Sua nutricionista está finalizando as opções de cada uma."
                : "Sua nutricionista está preparando o material desta categoria."
            }
          />
        ) : (
          temNiveis && (
            <div className="c-chips" style={{ marginTop: 18 }}>
              {FILTROS.map((opcao) => (
                <button
                  key={opcao.valor}
                  type="button"
                  className="c-chip"
                  aria-pressed={filtro === opcao.valor}
                  onClick={() => definirFiltro(opcao.valor)}
                >
                  {opcao.rotulo}
                </button>
              ))}
            </div>
          )
        )}

        {categoria.decisoes.map((decisao) => {
          const opcoes = decisao.opcoes.filter((o) => filtro === "todos" || o.nivel === filtro);
          if (totalDeOpcoes > 0 && opcoes.length === 0 && decisao.opcoes.length > 0) return null;
          return (
            <section className="c-decisao" key={decisao.id}>
              <h2>{decisao.titulo}</h2>
              {decisao.pergunta && <p className="c-decisao-pergunta">{decisao.pergunta}</p>}
              {decisao.observacoes.length > 0 && (
                <ul className="c-observacoes">
                  {decisao.observacoes.map((nota) => (
                    <li key={nota}>{nota}</li>
                  ))}
                </ul>
              )}
              {decisao.opcoes.length === 0 ? (
                <p className="c-contagem">Opções em preparação.</p>
              ) : (
                opcoes.map((opcao) => (
                  <CartaoOpcao
                    key={opcao.id}
                    opcao={opcao}
                    categoriaId={categoria.id}
                    categoriaNome={categoria.nome}
                    abertoInicialmente={opcao.id === opcaoDestacada}
                  />
                ))
              )}
            </section>
          );
        })}

        {categoria.lembretes.length > 0 && (
          <section className="c-secao c-prosa">
            <h2 className="c-secao-titulo">Para lembrar</h2>
            <ul>
              {categoria.lembretes.map((lembrete) => (
                <li key={lembrete}>{lembrete}</li>
              ))}
            </ul>
          </section>
        )}
      </div>
    </>
  );
}
