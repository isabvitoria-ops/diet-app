import type {
  Alimento,
  CategoriaComerFora,
  Configuracoes,
  Equivalencia,
  EventoHistorico,
  Favorito,
  GrupoAlimentar,
  Guia,
  NovoPaciente,
  Paciente,
  Plano,
  Unidade,
} from "@/central/types";
import { MODO_DEMONSTRACAO } from "@/central/supabase/cliente";
import { repositorioLocal } from "./repositorioLocal";
import { repositorioSupabase } from "./repositorioSupabase";

/**
 * A porta única entre o app e onde os dados moram (§2, §30 do briefing).
 *
 * Duas implementações atendem a mesma interface: `repositorioSupabase`, que
 * fala com o banco de verdade, e `repositorioLocal`, que usa os arquivos de
 * semente e o armazenamento do navegador. Quem escolhe é a presença das
 * variáveis de ambiente — nenhuma tela sabe qual das duas está respondendo.
 *
 * É por aqui que entraria um terceiro backend um dia, sem tocar em tela.
 */

export interface DadosCatalogo {
  unidades: Unidade[];
  grupos: GrupoAlimentar[];
  alimentos: Alimento[];
  equivalencias: Equivalencia[];
  categoriasComerFora: CategoriaComerFora[];
  guias: Guia[];
  configuracoes: Configuracoes;
}

export interface AlteracaoPaciente {
  nome?: string;
  email?: string;
  telefone?: string | null;
  planoId?: string | null;
  dataInicio?: string;
  dataFim?: string;
  status?: "convite_pendente" | "ativo" | "suspenso";
  observacoes?: string | null;
}

export interface Repositorio {
  /** Tudo que as telas do paciente precisam, numa carga só. */
  carregarCatalogo(): Promise<DadosCatalogo>;

  listarFavoritos(): Promise<Favorito[]>;
  salvarFavorito(favorito: Favorito): Promise<void>;
  removerFavorito(id: string): Promise<void>;

  listarPlanos(): Promise<Plano[]>;
  listarPacientes(): Promise<Paciente[]>;
  criarPaciente(dados: NovoPaciente): Promise<Paciente>;
  alterarPaciente(id: string, alteracao: AlteracaoPaciente): Promise<void>;
  excluirPaciente(id: string): Promise<void>;
  registrarConvite(pacienteId: string, email: string): Promise<void>;
  historicoDoPaciente(pacienteId: string): Promise<EventoHistorico[]>;

  salvarAlimento(alimento: Alimento, ativo: boolean): Promise<void>;
  salvarEquivalencia(equivalencia: Equivalencia, ativo: boolean): Promise<void>;
  salvarCategoriaComerFora(categoria: CategoriaComerFora): Promise<void>;
  salvarGuia(guia: Guia): Promise<void>;
  salvarConfiguracoes(configuracoes: Configuracoes): Promise<void>;

  /** Marca presença do paciente. Falha em silêncio: não é crítico. */
  registrarAcesso(): Promise<void>;
}

export const repositorio: Repositorio = MODO_DEMONSTRACAO ? repositorioLocal : repositorioSupabase;
