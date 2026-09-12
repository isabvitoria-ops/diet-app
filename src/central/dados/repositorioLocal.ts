import type {
  Alimento,
  CategoriaComerFora,
  Configuracoes,
  Equivalencia,
  EventoHistorico,
  Favorito,
  Guia,
  NovoPaciente,
  Paciente,
  Plano,
} from "@/central/types";
import { armazenamentoLocal } from "@/central/utils/armazenamento";
import { calcularSituacao, diasEntre, hojeSaoPaulo } from "@/central/utils/situacao";
import { UNIDADES } from "./sementes/unidades";
import { GRUPOS } from "./sementes/grupos";
import { ALIMENTOS } from "./sementes/alimentos";
import { EQUIVALENCIAS } from "./sementes/equivalencias";
import { CATEGORIAS_COMER_FORA } from "./sementes/comerFora";
import { GUIAS } from "./sementes/guias";
import { PLANOS } from "./sementes/planos";
import { CONFIGURACOES } from "./sementes/configuracoes";
import { paraConfiguracoes } from "./mapeadores";
import type { AlteracaoPaciente, DadosCatalogo, Repositorio } from "./repositorio";

/**
 * Modo demonstração: o app inteiro funcionando sem banco nenhum.
 *
 * Serve a três coisas: abrir o projeto e ver tudo antes de configurar
 * serviço algum; rodar a bateria de testes de interface sem depender de
 * rede; e ter para onde voltar se um dia o Supabase estiver fora do ar
 * durante o desenvolvimento.
 *
 * O que for salvo aqui fica no navegador de quem está usando e não vai para
 * lugar nenhum — a tela avisa isso o tempo todo, para ninguém confundir
 * demonstração com produção.
 */

const guardaAlimentos = armazenamentoLocal<Alimento>("central:demo:alimentos:v1");
const guardaEquivalencias = armazenamentoLocal<Equivalencia>("central:demo:equivalencias:v1");
const guardaComerFora = armazenamentoLocal<CategoriaComerFora>("central:demo:comer-fora:v1");
const guardaGuias = armazenamentoLocal<Guia>("central:demo:guias:v1");
const guardaFavoritos = armazenamentoLocal<Favorito>("central:favoritos:v1");
const guardaPacientes = armazenamentoLocal<Paciente>("central:demo:pacientes:v1");
const guardaHistorico = armazenamentoLocal<EventoHistorico>("central:demo:historico:v1");
const guardaConfiguracoes = armazenamentoLocal<[string, unknown]>("central:demo:config:v1");

/** Combina a semente com o que foi editado no navegador, sem duplicar. */
function mesclar<T extends { id: string }>(semente: T[], salvos: T[]): T[] {
  const mapa = new Map(semente.map((x) => [x.id, x]));
  for (const item of salvos) mapa.set(item.id, item);
  return [...mapa.values()];
}

function configuracoesAtuais(): Configuracoes {
  const salvas = guardaConfiguracoes.ler();
  const linhas = CONFIGURACOES.map((c) => {
    const sobrescrita = salvas.find(([chave]) => chave === c.chave);
    return { chave: c.chave, valor: sobrescrita ? sobrescrita[1] : c.valor };
  });
  return paraConfiguracoes(linhas);
}

function registrar(pacienteId: string, evento: string, detalhe: Record<string, unknown> = {}): void {
  const historico = guardaHistorico.ler();
  historico.unshift({
    id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    pacienteId,
    evento,
    detalhe,
    criadoEm: new Date().toISOString(),
  });
  guardaHistorico.escrever(historico.slice(0, 500));
}

/** Recalcula `situacao` e `diasRestantes` toda vez que a lista é lida. */
function comSituacao(paciente: Paciente, alertaDias: number): Paciente {
  const plano = PLANOS.find((p) => p.id === paciente.planoId);
  return {
    ...paciente,
    planoNome: plano?.nome ?? null,
    situacao: calcularSituacao(paciente, alertaDias),
    diasRestantes: diasEntre(hojeSaoPaulo(), paciente.dataFim),
  };
}

export const repositorioLocal: Repositorio = {
  async carregarCatalogo(): Promise<DadosCatalogo> {
    return {
      unidades: UNIDADES,
      grupos: GRUPOS,
      alimentos: mesclar(ALIMENTOS, guardaAlimentos.ler()),
      equivalencias: mesclar(EQUIVALENCIAS, guardaEquivalencias.ler()),
      categoriasComerFora: mesclar(CATEGORIAS_COMER_FORA, guardaComerFora.ler()),
      guias: mesclar(GUIAS, guardaGuias.ler()),
      configuracoes: configuracoesAtuais(),
    };
  },

  async listarFavoritos() {
    return guardaFavoritos.ler();
  },

  async salvarFavorito(favorito) {
    const atuais = guardaFavoritos.ler().filter((f) => f.id !== favorito.id);
    guardaFavoritos.escrever([favorito, ...atuais]);
  },

  async removerFavorito(id) {
    guardaFavoritos.escrever(guardaFavoritos.ler().filter((f) => f.id !== id));
  },

  async listarPlanos(): Promise<Plano[]> {
    return PLANOS.map((p) => ({ ...p, ativo: true }));
  },

  async listarPacientes() {
    const alerta = configuracoesAtuais().alertaVencimentoDias;
    return guardaPacientes
      .ler()
      .map((p) => comSituacao(p, alerta))
      .sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR"));
  },

  async criarPaciente(dados: NovoPaciente) {
    const paciente: Paciente = {
      id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
      // Em modo demonstração não há e-mail nem conta: o paciente já nasce
      // vinculado, senão não daria para experimentar as telas seguintes.
      perfilId: `demo-${Date.now()}`,
      email: dados.email.toLowerCase(),
      nome: dados.nome,
      telefone: dados.telefone ?? null,
      planoId: dados.planoId,
      planoNome: PLANOS.find((p) => p.id === dados.planoId)?.nome ?? null,
      dataInicio: dados.dataInicio,
      dataFim: dados.dataFim,
      status: "ativo",
      situacao: "ativo",
      diasRestantes: diasEntre(hojeSaoPaulo(), dados.dataFim),
      observacoes: dados.observacoes ?? null,
      ultimoAcesso: null,
      conviteEnviadoEm: new Date().toISOString(),
      criadoEm: new Date().toISOString(),
    };
    guardaPacientes.escrever([paciente, ...guardaPacientes.ler()]);
    registrar(paciente.id, "paciente_cadastrado", {
      plano: dados.planoId,
      inicio: dados.dataInicio,
      fim: dados.dataFim,
    });
    return comSituacao(paciente, configuracoesAtuais().alertaVencimentoDias);
  },

  async alterarPaciente(id, alteracao: AlteracaoPaciente) {
    const pacientes = guardaPacientes.ler();
    const antes = pacientes.find((p) => p.id === id);
    if (!antes) return;
    const depois = { ...antes, ...alteracao } as Paciente;
    guardaPacientes.escrever(pacientes.map((p) => (p.id === id ? depois : p)));

    if (alteracao.status && alteracao.status !== antes.status) {
      registrar(
        id,
        alteracao.status === "suspenso" ? "suspenso" : "reativado",
        { de: antes.status, para: alteracao.status },
      );
    } else if (alteracao.dataFim && alteracao.dataFim !== antes.dataFim) {
      registrar(id, "renovado", {
        fim_anterior: antes.dataFim,
        fim: alteracao.dataFim,
        plano: alteracao.planoId ?? antes.planoId,
      });
    }
  },

  async excluirPaciente(id) {
    guardaPacientes.escrever(guardaPacientes.ler().filter((p) => p.id !== id));
    guardaHistorico.escrever(guardaHistorico.ler().filter((e) => e.pacienteId !== id));
  },

  async registrarConvite(pacienteId) {
    const pacientes = guardaPacientes.ler();
    guardaPacientes.escrever(
      pacientes.map((p) =>
        p.id === pacienteId ? { ...p, conviteEnviadoEm: new Date().toISOString() } : p,
      ),
    );
    registrar(pacienteId, "convite_enviado");
  },

  async historicoDoPaciente(pacienteId) {
    return guardaHistorico.ler().filter((e) => e.pacienteId === pacienteId);
  },

  async salvarAlimento(alimento) {
    const salvos = guardaAlimentos.ler().filter((a) => a.id !== alimento.id);
    guardaAlimentos.escrever([...salvos, alimento]);
  },

  async salvarEquivalencia(equivalencia) {
    const salvas = guardaEquivalencias.ler().filter((e) => e.id !== equivalencia.id);
    guardaEquivalencias.escrever([...salvas, equivalencia]);
  },

  async salvarCategoriaComerFora(categoria) {
    const salvas = guardaComerFora.ler().filter((c) => c.id !== categoria.id);
    guardaComerFora.escrever([...salvas, categoria]);
  },

  async salvarGuia(guia) {
    const salvos = guardaGuias.ler().filter((g) => g.id !== guia.id);
    guardaGuias.escrever([...salvos, guia]);
  },

  async salvarConfiguracoes(configuracoes) {
    guardaConfiguracoes.escrever([
      ["nome_central", configuracoes.nomeCentral],
      ["frase_home", configuracoes.fraseHome],
      ["lema", configuracoes.lema],
      ["whatsapp", configuracoes.whatsapp],
      ["nome_nutricionista", configuracoes.nomeNutricionista],
      ["alerta_vencimento_dias", configuracoes.alertaVencimentoDias],
    ]);
  },

  async registrarAcesso() {
    /* não há o que registrar sem banco */
  },
};
