import { useState } from "react";
import { useParams } from "react-router-dom";
import type { NivelEscolha } from "@/central/types";
import { catalogo } from "@/central/dados/catalogo";
import { CabecalhoPagina } from "@/central/components/CabecalhoPagina";
import { CartaoOpcao } from "@/central/components/CartaoOpcao";
import { EstadoVazio } from "@/central/components/EstadoVazio";
import { BotaoFavorito } from "@/central/components/BotaoFavorito";
import { Logo } from "@/central/components/Logo";
import { rotas } from "@/central/rotas";

/**
 * Uma casa por dentro: o que pedir no McDonald's, no Spoleto.
 *
 * É a pergunta que a paciente faz parada no balcão, e por isso tem tela
 * própria em vez de virar mais uma seção espremida na categoria: aqui cabem
 * o filtro por classificação e a lista inteira do cardápio.
 */
const FILTROS: { valor: NivelEscolha | "todos"; rotulo: string }[] = [
  { valor: "todos", rotulo: "Todas" },
  { valor: "melhor", rotulo: "Melhor escolha" },
  { valor: "boa", rotulo: "Boa opção" },
  { valor: "ocasional", rotulo: "Mais ocasional" },
];

export function EstabelecimentoDetalhe() {
  const { categoriaId = "", estabelecimentoId = "" } = useParams();
  const [filtro, definirFiltro] = useState<NivelEscolha | "todos">("todos");

  const categoria = catalogo.categoriaComerFora(categoriaId);
  const casa = categoria?.estabelecimentos.find((e) => e.id === estabelecimentoId) ?? null;

  if (!categoria || !casa) {
    return (
      <>
        <CabecalhoPagina titulo="Lugar não encontrado" voltarPara={rotas.comerFora} />
        <div className="c-conteudo">
          <EstadoVazio titulo="Este lugar não está na lista" descricao="Volte e escolha outro." />
        </div>
      </>
    );
  }

  const temNiveis = casa.opcoes.some((o) => o.nivel !== null);
  const visiveis = casa.opcoes.filter((o) => filtro === "todos" || o.nivel === filtro);

  return (
    <>
      <CabecalhoPagina
        titulo={casa.nome}
        descricao={casa.resumo ?? categoria.nome}
        voltarPara={rotas.categoria(categoria.id)}
        acao={
          <BotaoFavorito
            item={{
              tipo: "categoria",
              refId: `${categoria.id}/${casa.id}`,
              titulo: casa.nome,
              subtitulo: categoria.nome,
              rota: rotas.estabelecimento(categoria.id, casa.id),
            }}
          />
        }
      />

      <div className="c-conteudo">
        <div className="c-casa-topo">
          <Logo nome={casa.nome} logo={casa.logo} tamanho={56} nomeVisivel={false} />
          {casa.grupo && <span className="c-contagem">{casa.grupo}</span>}
        </div>

        {casa.observacoes.length > 0 && (
          <ul className="c-observacoes" style={{ marginTop: 16 }}>
            {casa.observacoes.map((nota) => (
              <li key={nota}>{nota}</li>
            ))}
          </ul>
        )}

        {casa.opcoes.length === 0 ? (
          <EstadoVazio
            icone="comerFora"
            titulo="Opções em preparação"
            descricao={`Sua nutricionista está montando as escolhas do ${casa.nome}.`}
          />
        ) : (
          <>
            {temNiveis && (
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
            )}

            <section className="c-decisao">
              {visiveis.length === 0 ? (
                <p className="c-contagem" role="status">
                  Nenhuma opção nesta classificação.
                </p>
              ) : (
                visiveis.map((opcao) => (
                  <CartaoOpcao
                    key={opcao.id}
                    opcao={opcao}
                    categoriaId={categoria.id}
                    categoriaNome={`${categoria.nome} · ${casa.nome}`}
                  />
                ))
              )}
            </section>
          </>
        )}
      </div>
    </>
  );
}
