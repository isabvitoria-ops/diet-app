import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { catalogo } from "@/central/dados/catalogo";
import { BarraBusca } from "@/central/components/BarraBusca";
import { CabecalhoPagina } from "@/central/components/CabecalhoPagina";
import { Icone } from "@/central/components/Icone";
import { normalizar } from "@/central/utils/texto";
import { rotas } from "@/central/rotas";

/**
 * Substituições (§11) — a lista por grupo alimentar.
 *
 * Os grupos vêm de `data/grupos.ts`, não de uma lista fixa aqui: criar o
 * grupo "Laticínios" amanhã é uma linha de dado. A busca desta tela olha
 * nome do grupo e nome de alimento ao mesmo tempo, porque o paciente pensa
 * em "arroz", não em "carboidratos".
 */
export function Substituicoes() {
  const navegar = useNavigate();
  const [consulta, definirConsulta] = useState("");

  const grupos = useMemo(() => {
    const termo = normalizar(consulta);
    return catalogo.grupos().map((grupo) => {
      const alimentos = catalogo.alimentosDoGrupo(grupo.id);
      const combina =
        termo.length === 0 ||
        normalizar(grupo.nome).includes(termo) ||
        grupo.tags.some((t) => normalizar(t).includes(termo)) ||
        alimentos.some((a) => normalizar(a.nome).includes(termo));
      return { grupo, alimentos, combina };
    });
  }, [consulta]);

  const visiveis = grupos.filter((g) => g.combina);

  return (
    <>
      <CabecalhoPagina
        titulo="Substituições"
        descricao="Consulte suas opções de troca por grupo alimentar."
        voltarPara={rotas.home}
      />

      <div className="c-conteudo">
        <div style={{ marginTop: 18 }}>
          <BarraBusca valor={consulta} aoMudar={definirConsulta} placeholder="Buscar grupo ou alimento" rotulo="Buscar substituições" />
        </div>

        <section className="c-secao">
          <div className="c-lista">
            {visiveis.map(({ grupo, alimentos }) => {
              const cadastrados = alimentos.filter((a) => a.porcao !== null).length;
              return (
                <button
                  key={grupo.id}
                  type="button"
                  className="c-lista-item"
                  onClick={() => navegar(rotas.grupo(grupo.id))}
                >
                  <span>
                    <span className="c-lista-item-nome">{grupo.nome}</span>
                    <span className="c-lista-item-apoio">
                      {alimentos.length === 0
                        ? "Ainda sem alimentos cadastrados"
                        : grupo.regra?.tipo === "livre"
                          ? `${alimentos.length} alimentos · quantidade livre`
                          : `${alimentos.length} ${alimentos.length === 1 ? "alimento" : "alimentos"}${cadastrados > 0 ? ` · ${cadastrados} com porção` : ""}`}
                    </span>
                  </span>
                  <span className="c-lista-item-direita">
                    <Icone nome="seta" tamanho={17} />
                  </span>
                </button>
              );
            })}
          </div>

          {visiveis.length === 0 && <p className="c-contagem">Nenhum grupo ou alimento com esse nome.</p>}
        </section>
      </div>
    </>
  );
}
