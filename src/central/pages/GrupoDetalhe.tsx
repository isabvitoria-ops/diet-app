import { useMemo, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { catalogo } from "@/central/data/catalogo";
import { BarraBusca } from "@/central/components/BarraBusca";
import { CabecalhoPagina } from "@/central/components/CabecalhoPagina";
import { EstadoVazio } from "@/central/components/EstadoVazio";
import { Icone } from "@/central/components/Icone";
import { BotaoFavorito } from "@/central/components/BotaoFavorito";
import { SeloNeutro } from "@/central/components/Selo";
import { textoMedida } from "@/central/utils/medidas";
import { normalizar } from "@/central/utils/texto";
import { destinosPossiveis } from "@/central/utils/calculoTroca";
import { rotas } from "@/central/rotas";

/**
 * Um grupo alimentar por dentro: a regra do grupo, os alimentos e a porção
 * de cada um.
 *
 * Alimento sem porção cadastrada aparece marcado como "porção a definir" —
 * o briefing (§29) pede para deixar a lacuna visível em vez de preenchê-la.
 * Quem tem troca disponível ganha um atalho direto para a calculadora.
 */
export function GrupoDetalhe() {
  const { grupoId = "" } = useParams();
  const navegar = useNavigate();
  const [consulta, definirConsulta] = useState("");

  const grupo = catalogo.grupo(grupoId);
  const alimentos = useMemo(() => (grupo ? catalogo.alimentosDoGrupo(grupo.id) : []), [grupo]);

  const visiveis = useMemo(() => {
    const termo = normalizar(consulta);
    if (!termo) return alimentos;
    return alimentos.filter(
      (a) => normalizar(a.nome).includes(termo) || a.tags.some((t) => normalizar(t).includes(termo)),
    );
  }, [alimentos, consulta]);

  if (!grupo) {
    return (
      <>
        <CabecalhoPagina titulo="Grupo não encontrado" voltarPara={rotas.substituicoes} />
        <div className="c-conteudo">
          <EstadoVazio titulo="Este grupo não existe" descricao="Talvez ele tenha sido renomeado. Volte e escolha outro." />
        </div>
      </>
    );
  }

  return (
    <>
      <CabecalhoPagina
        titulo={grupo.nome}
        descricao={grupo.descricao}
        voltarPara={rotas.substituicoes}
        acao={
          <BotaoFavorito
            item={{ tipo: "grupo", refId: grupo.id, titulo: grupo.nome, subtitulo: grupo.descricao, rota: rotas.grupo(grupo.id) }}
          />
        }
      />

      <div className="c-conteudo">
        {grupo.regra?.tipo === "livre" && (
          <div className="c-regra">
            <strong>Quantidade livre.</strong>{" "}
            {grupo.regra.minimos.length > 0 && (
              <>
                Porção mínima de{" "}
                {grupo.regra.minimos
                  .map((m) => `${textoMedida(m.medida, catalogo.unidade(m.medida.unidadeId))} no ${m.refeicao.toLowerCase()}`)
                  .join(" e ")}
                .
              </>
            )}
          </div>
        )}

        {alimentos.length > 6 && (
          <div style={{ marginTop: 18 }}>
            <BarraBusca valor={consulta} aoMudar={definirConsulta} placeholder={`Buscar em ${grupo.nome.toLowerCase()}`} rotulo="Buscar alimento" />
          </div>
        )}

        {alimentos.length === 0 ? (
          <EstadoVazio
            icone="lista"
            titulo="Ainda sem alimentos"
            descricao="Sua nutricionista ainda não cadastrou alimentos neste grupo. Assim que cadastrar, eles aparecem aqui."
          />
        ) : (
          <section className="c-secao">
            <h2 className="c-secao-titulo">
              {visiveis.length} {visiveis.length === 1 ? "alimento" : "alimentos"}
            </h2>
            <div className="c-lista">
              {visiveis.map((alimento) => {
                const temTroca = destinosPossiveis(alimento).length > 0;
                const unidade = alimento.porcao ? catalogo.unidade(alimento.porcao.unidadeId) : null;
                return (
                  <div key={alimento.id} className="c-lista-item" style={{ cursor: temTroca ? "pointer" : "default" }}
                    onClick={() => temTroca && navegar(rotas.trocaCom(alimento.id))}
                  >
                    <span>
                      <span className="c-lista-item-nome">{alimento.nome}</span>
                      <span className="c-lista-item-apoio">
                        {alimento.porcao
                          ? `1 porção · ${textoMedida(alimento.porcao, unidade)}`
                          : grupo.regra?.tipo === "livre"
                            ? "Quantidade livre"
                            : "Porção a definir"}
                      </span>
                    </span>
                    <span className="c-lista-item-direita">
                      {temTroca ? (
                        <Icone nome="troca" tamanho={17} />
                      ) : (
                        grupo.regra?.tipo !== "livre" && <SeloNeutro>Em cadastro</SeloNeutro>
                      )}
                      <BotaoFavorito
                        item={{
                          tipo: "alimento",
                          refId: alimento.id,
                          titulo: alimento.nome,
                          subtitulo: grupo.nome,
                          rota: temTroca ? rotas.trocaCom(alimento.id) : rotas.grupo(grupo.id),
                        }}
                      />
                    </span>
                  </div>
                );
              })}
            </div>
            {visiveis.length === 0 && <p className="c-contagem">Nenhum alimento com esse nome neste grupo.</p>}
          </section>
        )}
      </div>
    </>
  );
}
