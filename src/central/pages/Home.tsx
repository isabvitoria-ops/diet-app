import { useNavigate } from "react-router-dom";
import { Icone, type NomeIcone } from "@/central/components/Icone";
import { BarraBusca } from "@/central/components/BarraBusca";
import { useState } from "react";
import { rotas } from "@/central/rotas";
import { useFavoritos } from "@/central/hooks/useFavoritos";

/**
 * Home — a "Central do Paciente" (§3 e §33).
 *
 * A tela responde à pergunta "o que eu vim fazer aqui?" em um olhar: uma
 * busca no topo, para quem já sabe o que quer, e cinco portas grandes, para
 * quem está só procurando. Nada de conteúdo institucional.
 */
const ATALHOS: { rota: string; icone: NomeIcone; titulo: string; descricao: string }[] = [
  {
    rota: rotas.trocas,
    icone: "troca",
    titulo: "Troca inteligente",
    descricao: "Substitua alimentos mantendo a quantidade adequada.",
  },
  {
    rota: rotas.comerFora,
    icone: "comerFora",
    titulo: "Comer fora",
    descricao: "Estratégias para escolher melhor fora de casa.",
  },
  {
    rota: rotas.substituicoes,
    icone: "lista",
    titulo: "Substituições",
    descricao: "Suas opções de troca por grupo alimentar.",
  },
  {
    rota: rotas.guias,
    icone: "guias",
    titulo: "Guias",
    descricao: "Orientações práticas para situações do dia a dia.",
  },
  {
    rota: rotas.salvos,
    icone: "salvos",
    titulo: "Salvos",
    descricao: "Seus conteúdos guardados.",
  },
];

export function Home() {
  const navegar = useNavigate();
  const [consulta, definirConsulta] = useState("");
  const salvos = useFavoritos((estado) => estado.itens.length);

  return (
    <>
      <header className="c-cabecalho">
        <div className="c-cabecalho-linha">
          <div>
            <p className="c-marca">Central do paciente</p>
            <h1 className="c-titulo">Facilite suas escolhas no dia a dia.</h1>
          </div>
        </div>
      </header>

      <div className="c-conteudo">
        <div style={{ marginTop: 22 }}>
          <BarraBusca
            valor={consulta}
            aoMudar={definirConsulta}
            aoEnviar={() => navegar(rotas.busca(consulta))}
            placeholder="O que você está procurando?"
          />
        </div>

        {consulta.trim().length > 0 && (
          <button type="button" className="c-chip" style={{ marginTop: 12 }} onClick={() => navegar(rotas.busca(consulta))}>
            <Icone nome="busca" tamanho={14} />
            Buscar por “{consulta.trim()}”
          </button>
        )}

        <section className="c-secao">
          <div className="c-atalhos">
            {ATALHOS.map((atalho) => (
              <button key={atalho.rota} type="button" className="c-atalho" onClick={() => navegar(atalho.rota)}>
                <span className="c-atalho-icone">
                  <Icone nome={atalho.icone} tamanho={22} />
                </span>
                <span className="c-atalho-texto">
                  <h3>{atalho.titulo}</h3>
                  <p>
                    {atalho.rota === rotas.salvos && salvos > 0
                      ? `${salvos} ${salvos === 1 ? "item guardado" : "itens guardados"}.`
                      : atalho.descricao}
                  </p>
                </span>
                <span className="c-atalho-seta">
                  <Icone nome="seta" tamanho={18} />
                </span>
              </button>
            ))}
          </div>
        </section>
      </div>
    </>
  );
}
