import { useCallback, useEffect, useState } from "react";
import type {
  DesafioAdmin,
  EnvioPendente,
  IndicacaoPendente,
  LinhaDoRanking,
  PainelDoDesafio,
} from "@/central/types";
import { repositorio } from "@/central/dados/repositorio";
import { dataBonita, hojeSaoPaulo } from "@/central/utils/situacao";
import { SeloNeutro } from "@/central/components/Selo";
import { Campo, Selecao, Texto, AreaTexto } from "./componentes/Campos";
import { Modal } from "./componentes/Modal";

/**
 * Desafio do Mês — área da nutricionista.
 *
 * Quatro abas porque são quatro trabalhos diferentes: ver como vai, conferir
 * o que chegou, olhar o ranking e cuidar das indicações. Nenhuma delas soma
 * ponto: aprovar e recusar chamam a função do banco, e o resultado volta da
 * leitura seguinte.
 */
const ABAS = ["Visão geral", "Pendências", "Ranking", "Indicações"] as const;
type Aba = (typeof ABAS)[number];

const SITUACOES: Record<string, string> = {
  rascunho: "Rascunho",
  agendado: "Agendado",
  ativo: "No ar",
  encerrado: "Encerrado",
};

export function Desafios() {
  const [desafios, definirDesafios] = useState<DesafioAdmin[]>([]);
  const [escolhido, definirEscolhido] = useState<string | null>(null);
  const [aba, definirAba] = useState<Aba>("Visão geral");
  const [editando, definirEditando] = useState<DesafioAdmin | "novo" | null>(null);
  const [erro, definirErro] = useState<string | null>(null);
  const [carregando, definirCarregando] = useState(true);

  const carregar = useCallback(async () => {
    try {
      const lista = await repositorio.listarDesafios();
      definirDesafios(lista);
      definirEscolhido((atual) => atual ?? lista.find((d) => d.situacao === "ativo")?.id ?? lista[0]?.id ?? null);
      definirErro(null);
    } catch (e) {
      definirErro(e instanceof Error ? e.message : "Não consegui carregar os desafios.");
    } finally {
      definirCarregando(false);
    }
  }, []);

  useEffect(() => {
    void carregar();
  }, [carregar]);

  const desafio = desafios.find((d) => d.id === escolhido) ?? null;

  return (
    <>
      <div className="c-admin-topo-linha" style={{ marginBottom: 4 }}>
        <div>
          <h1 className="c-titulo" style={{ fontSize: 28 }}>Desafio do mês</h1>
          <p className="c-subtitulo">
            Marcar não dá pontos. Os pontos entram quando você aprova, e o ranking se atualiza sozinho.
          </p>
        </div>
        <button type="button" className="c-botao c-botao-pequeno" onClick={() => definirEditando("novo")}>
          Novo desafio
        </button>
      </div>

      {erro && (
        <div className="c-aviso c-aviso-erro" role="alert">
          <span>{erro}</span>
        </div>
      )}

      {carregando ? (
        <p className="c-contagem">Carregando…</p>
      ) : desafios.length === 0 ? (
        <p className="c-contagem">Nenhum desafio criado ainda.</p>
      ) : (
        <>
          <div className="c-chips" style={{ marginTop: 14 }}>
            {desafios.map((d) => (
              <button
                key={d.id}
                type="button"
                className="c-chip"
                aria-pressed={d.id === escolhido}
                onClick={() => definirEscolhido(d.id)}
              >
                {d.nome} · {SITUACOES[d.situacao] ?? d.situacao}
              </button>
            ))}
          </div>

          {desafio && (
            <>
              <div className="c-admin-abas" style={{ marginTop: 16 }}>
                {ABAS.map((a) => (
                  <button
                    key={a}
                    type="button"
                    className={`c-admin-aba ${a === aba ? "ativo" : ""}`}
                    onClick={() => definirAba(a)}
                  >
                    {a}
                  </button>
                ))}
              </div>

              <div style={{ marginTop: 18 }}>
                {aba === "Visão geral" && (
                  <VisaoGeral desafio={desafio} aoEditar={() => definirEditando(desafio)} />
                )}
                {aba === "Pendências" && <Pendencias desafioId={desafio.id} />}
                {aba === "Ranking" && <Ranking desafioId={desafio.id} />}
                {aba === "Indicações" && <Indicacoes />}
              </div>
            </>
          )}
        </>
      )}

      {editando && (
        <ModalDesafio
          desafio={editando === "novo" ? null : editando}
          aoFechar={() => {
            definirEditando(null);
            void carregar();
          }}
        />
      )}
    </>
  );
}

// ---------------------------------------------------------------- visão geral

function VisaoGeral({ desafio, aoEditar }: { desafio: DesafioAdmin; aoEditar: () => void }) {
  const [painel, definirPainel] = useState<PainelDoDesafio | null>(null);

  useEffect(() => {
    void repositorio.painelDoDesafio(desafio.id).then(definirPainel).catch(() => definirPainel(null));
  }, [desafio.id]);

  return (
    <>
      <div className="c-bloco">
        <div className="c-bloco-topo">
          <strong style={{ fontSize: 15 }}>{desafio.nome}</strong>
          <button type="button" className="c-link" onClick={aoEditar}>
            Editar
          </button>
        </div>
        <p className="c-contagem">
          {dataBonita(desafio.dataInicio)} — {dataBonita(desafio.dataFim)} ·{" "}
          {SITUACOES[desafio.situacao] ?? desafio.situacao}
          {desafio.semanaAtual ? ` · semana ${desafio.semanaAtual} de ${desafio.totalDeSemanas}` : ""}
        </p>
        {desafio.lema && <p className="c-dica">{desafio.lema}</p>}
      </div>

      {painel && (
        <div className="c-numeros">
          <Numero rotulo="Elegíveis" valor={painel.elegiveis} />
          <Numero rotulo="Participantes" valor={painel.participantes} />
          <Numero rotulo="Sem nenhuma ação" valor={painel.semAcao} />
          <Numero rotulo="Aguardando você" valor={painel.pendentes} destaque={painel.pendentes > 0} />
          <Numero rotulo="Maior pontuação" valor={painel.maiorPontuacao} />
          <Numero rotulo="Média" valor={painel.media} />
        </div>
      )}

      {painel && painel.acoesMaisFeitas.length > 0 && (
        <div className="c-bloco" style={{ marginTop: 14 }}>
          <strong style={{ fontSize: 14 }}>Ações mais realizadas</strong>
          <div className="c-ranking" style={{ marginTop: 10 }}>
            {painel.acoesMaisFeitas.map((a) => (
              <div key={a.nome} className="c-ranking-linha">
                <span className="c-ranking-nome">{a.nome}</span>
                <span className="c-ranking-pontos">{a.total}</span>
              </div>
            ))}
          </div>
        </div>
      )}
    </>
  );
}

function Numero({ rotulo, valor, destaque }: { rotulo: string; valor: number; destaque?: boolean }) {
  return (
    <div className={`c-numero ${destaque ? "destaque" : ""}`}>
      <strong>{valor}</strong>
      <span>{rotulo}</span>
    </div>
  );
}

// ---------------------------------------------------------------- pendências

function Pendencias({ desafioId }: { desafioId: string }) {
  const [lista, definirLista] = useState<EnvioPendente[]>([]);
  const [ocupado, definirOcupado] = useState<string | null>(null);
  const [erro, definirErro] = useState<string | null>(null);
  const [recusando, definirRecusando] = useState<EnvioPendente | null>(null);
  const [motivo, definirMotivo] = useState("");

  const carregar = useCallback(async () => {
    try {
      definirLista(await repositorio.enviosPendentes(desafioId));
    } catch (e) {
      definirErro(e instanceof Error ? e.message : "Não consegui carregar.");
    }
  }, [desafioId]);

  useEffect(() => {
    void carregar();
  }, [carregar]);

  async function executar(id: string, acao: () => Promise<void>) {
    definirOcupado(id);
    definirErro(null);
    try {
      await acao();
      await carregar();
    } catch (e) {
      definirErro(e instanceof Error ? e.message : "Não consegui salvar.");
    } finally {
      definirOcupado(null);
    }
  }

  if (lista.length === 0) {
    return <p className="c-contagem">Nada aguardando conferência.</p>;
  }

  return (
    <>
      {erro && (
        <div className="c-aviso c-aviso-erro" role="alert">
          <span>{erro}</span>
        </div>
      )}
      <div className="c-acoes">
        {lista.map((envio) => (
          <article className="c-acao" key={envio.id}>
            <div className="c-acao-topo">
              <span className="c-acao-texto">
                <strong>{envio.pacienteNome}</strong>
                <span className="c-acao-descricao">
                  {envio.acaoNome}
                  {envio.semana ? ` · semana ${envio.semana}` : ""} ·{" "}
                  {dataBonita(envio.enviadoEm.slice(0, 10))}
                </span>
                {envio.observacao && <span className="c-acao-descricao">“{envio.observacao}”</span>}
              </span>
              <span className="c-acao-pontos">+{envio.pontos}</span>
            </div>
            <div className="c-acao-estado">
              <button
                type="button"
                className="c-botao c-botao-pequeno"
                disabled={ocupado === envio.id}
                onClick={() => void executar(envio.id, () => repositorio.aprovarEnvio(envio.id))}
              >
                Aprovar
              </button>
              <button
                type="button"
                className="c-botao c-botao-secundario c-botao-pequeno"
                disabled={ocupado === envio.id}
                onClick={() => {
                  definirRecusando(envio);
                  definirMotivo("");
                }}
              >
                Recusar
              </button>
            </div>
          </article>
        ))}
      </div>

      {recusando && (
        <Modal titulo="Recusar" aoFechar={() => definirRecusando(null)}>
          <p className="c-dica">
            {recusando.pacienteNome} · {recusando.acaoNome}. Nenhum ponto será lançado.
          </p>
          <Campo rotulo="Motivo (a paciente vê)" dica="Opcional, mas ajuda a entender.">
            <AreaTexto valor={motivo} aoMudar={definirMotivo} linhas={2} />
          </Campo>
          <div className="c-modal-acoes">
            <button type="button" className="c-botao c-botao-secundario" onClick={() => definirRecusando(null)}>
              Cancelar
            </button>
            <button
              type="button"
              className="c-botao"
              onClick={() => {
                const alvo = recusando;
                definirRecusando(null);
                void executar(alvo.id, () => repositorio.recusarEnvio(alvo.id, motivo));
              }}
            >
              Recusar
            </button>
          </div>
        </Modal>
      )}
    </>
  );
}

// ---------------------------------------------------------------- ranking

function Ranking({ desafioId }: { desafioId: string }) {
  const [lista, definirLista] = useState<LinhaDoRanking[]>([]);
  const [busca, definirBusca] = useState("");

  useEffect(() => {
    void repositorio.rankingDoDesafio(desafioId).then(definirLista).catch(() => definirLista([]));
  }, [desafioId]);

  const visiveis = lista.filter((l) => l.nome.toLowerCase().includes(busca.trim().toLowerCase()));

  if (lista.length === 0) return <p className="c-contagem">Ninguém pontuou ainda.</p>;

  return (
    <>
      <Campo rotulo="Buscar paciente">
        <Texto valor={busca} aoMudar={definirBusca} placeholder="Nome" />
      </Campo>
      <div className="c-ranking" style={{ marginTop: 12 }}>
        {visiveis.map((l) => (
          <div key={`${l.posicao}-${l.nome}`} className={`c-ranking-linha ${l.posicao <= 3 ? "destaque" : ""}`}>
            <span className="c-ranking-posicao">{l.posicao}º</span>
            <span className="c-ranking-nome">{l.nome}</span>
            <span className="c-ranking-pontos">{l.pontos} pts</span>
          </div>
        ))}
      </div>
    </>
  );
}

// ---------------------------------------------------------------- indicações

const STATUS_INDICACAO: Record<string, string> = {
  registrada: "Registrada",
  iniciou: "Começou",
  validada: "Validada · +50",
  recusada: "Recusada",
};

function Indicacoes() {
  const [lista, definirLista] = useState<IndicacaoPendente[]>([]);
  const [ocupado, definirOcupado] = useState<string | null>(null);
  const [erro, definirErro] = useState<string | null>(null);

  const carregar = useCallback(async () => {
    try {
      definirLista(await repositorio.listarIndicacoes());
    } catch (e) {
      definirErro(e instanceof Error ? e.message : "Não consegui carregar.");
    }
  }, []);

  useEffect(() => {
    void carregar();
  }, [carregar]);

  async function executar(id: string, acao: () => Promise<void>) {
    definirOcupado(id);
    try {
      await acao();
      await carregar();
    } catch (e) {
      definirErro(e instanceof Error ? e.message : "Não consegui salvar.");
    } finally {
      definirOcupado(null);
    }
  }

  if (lista.length === 0) return <p className="c-contagem">Nenhuma indicação registrada.</p>;

  return (
    <>
      {erro && (
        <div className="c-aviso c-aviso-erro" role="alert">
          <span>{erro}</span>
        </div>
      )}
      <p className="c-dica">
        Os 50 pontos só entram quando você confirma que a indicada começou o acompanhamento.
      </p>
      <div className="c-acoes">
        {lista.map((i) => (
          <article className="c-acao" key={i.id}>
            <div className="c-acao-topo">
              <span className="c-acao-texto">
                <strong>{i.nomeIndicada}</strong>
                <span className="c-acao-descricao">
                  Indicada por {i.indicadoraNome} · {dataBonita(i.criadoEm.slice(0, 10))}
                </span>
                {i.emailIndicada && <span className="c-acao-descricao">{i.emailIndicada}</span>}
              </span>
              <SeloNeutro>{STATUS_INDICACAO[i.status] ?? i.status}</SeloNeutro>
            </div>
            {i.status !== "validada" && i.status !== "recusada" && (
              <div className="c-acao-estado">
                <button
                  type="button"
                  className="c-botao c-botao-pequeno"
                  disabled={ocupado === i.id}
                  onClick={() => void executar(i.id, () => repositorio.validarIndicacao(i.id))}
                >
                  Começou o acompanhamento · +50
                </button>
                <button
                  type="button"
                  className="c-link"
                  disabled={ocupado === i.id}
                  onClick={() => void executar(i.id, () => repositorio.recusarIndicacao(i.id))}
                >
                  Não começou
                </button>
              </div>
            )}
          </article>
        ))}
      </div>
    </>
  );
}

// ---------------------------------------------------------------- criar/editar

const STATUS_OPCOES = [
  { valor: "rascunho", rotulo: "Rascunho (ninguém vê)" },
  { valor: "ativo", rotulo: "No ar" },
  { valor: "encerrado", rotulo: "Encerrado" },
];

function ModalDesafio({ desafio, aoFechar }: { desafio: DesafioAdmin | null; aoFechar: () => void }) {
  const hoje = hojeSaoPaulo();
  const [ano, mes] = hoje.split("-").map(Number) as [number, number];
  const primeiro = `${ano}-${String(mes).padStart(2, "0")}-01`;
  const ultimo = `${ano}-${String(mes).padStart(2, "0")}-${new Date(Date.UTC(ano, mes, 0)).getUTCDate()}`;

  const [nome, definirNome] = useState(desafio?.nome ?? "");
  const [lema, definirLema] = useState(desafio?.lema ?? "Cada pequena ação conta.");
  const [descricao, definirDescricao] = useState(desafio?.descricao ?? "");
  const [regras, definirRegras] = useState(desafio?.regras ?? "");
  const [inicio, definirInicio] = useState(desafio?.dataInicio ?? primeiro);
  const [fim, definirFim] = useState(desafio?.dataFim ?? ultimo);
  const [status, definirStatus] = useState<string>(desafio?.status ?? "rascunho");
  const [aviso, definirAviso] = useState<string | null>(null);
  const [salvando, definirSalvando] = useState(false);

  async function salvar() {
    definirAviso(null);
    if (!nome.trim()) return definirAviso("Escreva o nome do desafio.");
    if (fim < inicio) return definirAviso("A data de fim não pode ser antes da de início.");
    definirSalvando(true);
    try {
      await repositorio.salvarDesafio({
        id: desafio?.id,
        nome: nome.trim(),
        lema: lema.trim() || null,
        descricao: descricao.trim() || null,
        regras: regras.trim() || null,
        dataInicio: inicio,
        dataFim: fim,
        status: status as DesafioAdmin["status"],
      });
      aoFechar();
    } catch (e) {
      definirAviso(e instanceof Error ? e.message : "Não consegui salvar.");
    } finally {
      definirSalvando(false);
    }
  }

  return (
    <Modal titulo={desafio ? "Editar desafio" : "Novo desafio"} aoFechar={aoFechar}>
      <Campo rotulo="Nome">
        <Texto valor={nome} aoMudar={definirNome} placeholder="Desafio de Outubro" />
      </Campo>
      <Campo rotulo="Lema" dica="A frase que abre a tela da paciente.">
        <Texto valor={lema} aoMudar={definirLema} />
      </Campo>
      <div className="c-duas-colunas">
        <Campo rotulo="Início">
          <Texto valor={inicio} aoMudar={definirInicio} tipo="date" />
        </Campo>
        <Campo rotulo="Fim">
          <Texto valor={fim} aoMudar={definirFim} tipo="date" />
        </Campo>
      </div>
      <Campo rotulo="Situação" dica="Rascunho não aparece para ninguém. Encerra sozinho na data de fim.">
        <Selecao valor={status} aoMudar={definirStatus} opcoes={STATUS_OPCOES} />
      </Campo>
      <Campo rotulo="Descrição">
        <AreaTexto valor={descricao} aoMudar={definirDescricao} linhas={2} />
      </Campo>
      <Campo rotulo="Como funciona" dica="Texto no fim da tela, explicando as regras.">
        <AreaTexto valor={regras} aoMudar={definirRegras} linhas={3} />
      </Campo>

      {desafio === null && (
        <p className="c-dica">
          As cinco ações e a pontuação vêm do desafio anterior. Para mudar valores, me chame.
        </p>
      )}

      {aviso && (
        <div className="c-aviso c-aviso-erro" role="alert">
          <span>{aviso}</span>
        </div>
      )}
      <div className="c-modal-acoes">
        <button type="button" className="c-botao c-botao-secundario" onClick={aoFechar}>
          Cancelar
        </button>
        <button type="button" className="c-botao" onClick={() => void salvar()} disabled={salvando}>
          {salvando ? "Salvando…" : "Salvar"}
        </button>
      </div>
    </Modal>
  );
}
