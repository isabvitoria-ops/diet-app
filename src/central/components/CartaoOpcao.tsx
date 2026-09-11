import { useState } from "react";
import type { OpcaoComerFora } from "@/central/types";
import { Icone } from "./Icone";
import { Selo } from "./Selo";
import { BotaoFavorito } from "./BotaoFavorito";
import { rotas } from "@/central/rotas";

/**
 * Cartão de opção de "Comer fora" (§14).
 *
 * O briefing pede cartões interativos, não PDF virado em página: o cartão
 * mostra o essencial fechado (o que é e como se encaixa) e abre para o
 * detalhe. As calorias (§16) só aparecem quando `mostrarKcal` está ligado
 * naquele item — o número fica guardado de qualquer jeito.
 */
export function CartaoOpcao({
  opcao,
  categoriaId,
  categoriaNome,
  abertoInicialmente = false,
}: {
  opcao: OpcaoComerFora;
  categoriaId: string;
  categoriaNome: string;
  abertoInicialmente?: boolean;
}) {
  const [aberto, definirAberto] = useState(abertoInicialmente);
  const temCorpo = Boolean(opcao.descricao) || opcao.detalhes.length > 0 || Boolean(opcao.energia?.mostrarKcal);

  return (
    <article className="c-opcao">
      <button
        type="button"
        className="c-opcao-topo"
        aria-expanded={temCorpo ? aberto : undefined}
        onClick={() => temCorpo && definirAberto((v) => !v)}
        style={{ cursor: temCorpo ? "pointer" : "default" }}
      >
        <span style={{ flex: 1 }}>
          <span className="c-opcao-titulo">{opcao.titulo}</span>
          {opcao.nivel && (
            <span style={{ display: "block", marginTop: 7 }}>
              <Selo nivel={opcao.nivel} />
            </span>
          )}
        </span>
        <span style={{ display: "flex", alignItems: "center", gap: 8, flex: "none" }}>
          <BotaoFavorito
            item={{
              tipo: "opcao",
              refId: `${categoriaId}:${opcao.id}`,
              titulo: opcao.titulo,
              subtitulo: categoriaNome,
              rota: rotas.opcao(categoriaId, opcao.id),
            }}
          />
          {temCorpo && (
            <Icone
              nome="seta"
              tamanho={17}
              style={{ transform: aberto ? "rotate(90deg)" : "none", transition: "transform .16s ease", color: "var(--text-subtle)" }}
            />
          )}
        </span>
      </button>

      {aberto && temCorpo && (
        <div className="c-opcao-corpo">
          {opcao.descricao && <p>{opcao.descricao}</p>}
          {opcao.detalhes.length > 0 && (
            <ul>
              {opcao.detalhes.map((detalhe) => (
                <li key={detalhe}>{detalhe}</li>
              ))}
            </ul>
          )}
          {opcao.energia?.mostrarKcal && opcao.energia.kcal !== null && (
            <p className="c-opcao-kcal">
              Cerca de {opcao.energia.kcal} kcal
              {opcao.energia.observacao ? ` · ${opcao.energia.observacao}` : ""}
            </p>
          )}
        </div>
      )}
    </article>
  );
}
