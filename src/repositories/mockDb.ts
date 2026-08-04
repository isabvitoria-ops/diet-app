import * as mocks from "@/data/mocks";
import type {
  AlertaClinico, CheckIn, Conversa, Mensagem, Nutricionista, Paciente, Plano, PostFeed,
  PreferenciasNotificacao, RegistroDiario, RespostaQuestionario, SessaoFoto, RegistroPeso,
} from "@/types";

/**
 * "Banco" em memória usado pelos repositories enquanto não há Supabase
 * plugado. Cada repository só fala com este arquivo — nenhum componente ou
 * service importa `@/data/mocks` diretamente. Trocar isto por chamadas
 * Supabase reais não deve exigir mudar nada fora de `repositories/`.
 */
function clone<T>(v: T): T {
  return JSON.parse(JSON.stringify(v)) as T;
}

const CHAVE_PERSISTENCIA = "diet-app:mock-db";
const VERSAO_PERSISTENCIA = 1;

// Declarado antes de `carregar()`, que restaura o valor salvo — o `db` é
// inicializado no topo do módulo e leria isto na zona morta temporal.
let contadorId = 1000;

const sementes = () => ({
  nutricionista: clone(mocks.NUTRICIONISTA) as Nutricionista,
  pacientes: clone(mocks.PACIENTES) as Paciente[],
  resumosAdesao: clone(mocks.RESUMOS_ADESAO),
  planos: [clone(mocks.PLANO_MARINA)] as Plano[],
  historicoVersoes: clone(mocks.HISTORICO_VERSOES_MARINA),
  montadorPools: { [mocks.PACIENTE_MARINA_ID]: clone(mocks.MONTADOR_POOL_MARINA) } as Record<string, typeof mocks.MONTADOR_POOL_MARINA>,
  fichasAlimento: clone(mocks.FICHAS_ALIMENTO),
  materiais: clone(mocks.MATERIAIS),
  artigosBiblioteca: clone(mocks.ARTIGOS_BIBLIOTECA),
  conversas: [clone(mocks.CONVERSA_MARINA)] as Conversa[],
  mensagens: clone(mocks.MENSAGENS_MARINA) as Mensagem[],
  posts: clone(mocks.POSTS_FEED) as PostFeed[],
  curtidas: clone(mocks.CURTIDAS_BASE) as Record<string, number>,
  curtidasPorPaciente: {} as Record<string, Set<string>>,
  templatesQuestionario: [clone(mocks.TEMPLATE_MENSAL)],
  respostasQuestionario: [] as RespostaQuestionario[],
  preferencias: { [mocks.PACIENTE_MARINA_ID]: clone(mocks.PREFERENCIAS_MARINA) } as Record<string, PreferenciasNotificacao>,
  consentimentos: clone(mocks.CONSENTIMENTOS),
  checkins: clone(mocks.HISTORICO_CHECKINS_MARINA) as CheckIn[],
  registrosDiario: clone(mocks.REGISTROS_DIARIO_INICIAIS) as RegistroDiario[],
  sessoesFoto: clone(mocks.SESSOES_FOTO_MARINA) as SessaoFoto[],
  pesos: [] as RegistroPeso[],
  alertasClinicos: [] as AlertaClinico[],
});

type BancoMock = ReturnType<typeof sementes>;

/**
 * O "banco" só existia na memória da aba, e isso aparecia como bug de
 * produto: a nutricionista publicava um post ou um plano, a paciente abria o
 * app e não havia nada — cada carregamento de página ressemeava tudo do
 * zero. Enquanto o Supabase não entra, o estado é espelhado no localStorage
 * para durar entre recargas e ser o mesmo nas duas abas da mesma origem.
 *
 * `Set` não sobrevive a JSON, então `curtidasPorPaciente` vai e volta como
 * lista.
 */
function serializar(banco: BancoMock): string {
  const curtidasPorPaciente: Record<string, string[]> = {};
  for (const [pacienteId, postIds] of Object.entries(banco.curtidasPorPaciente)) {
    curtidasPorPaciente[pacienteId] = [...postIds];
  }
  return JSON.stringify({ versao: VERSAO_PERSISTENCIA, contadorId, dados: { ...banco, curtidasPorPaciente } });
}

function carregar(): BancoMock | null {
  if (typeof localStorage === "undefined") return null;
  try {
    const bruto = localStorage.getItem(CHAVE_PERSISTENCIA);
    if (!bruto) return null;
    const salvo = JSON.parse(bruto) as { versao?: number; contadorId?: number; dados?: unknown };
    // Mudou a forma das sementes: recomeça em vez de misturar formatos.
    if (salvo.versao !== VERSAO_PERSISTENCIA || !salvo.dados) return null;

    const dados = salvo.dados as BancoMock & { curtidasPorPaciente: Record<string, string[]> };
    const curtidasPorPaciente: Record<string, Set<string>> = {};
    for (const [pacienteId, postIds] of Object.entries(dados.curtidasPorPaciente ?? {})) {
      curtidasPorPaciente[pacienteId] = new Set(postIds);
    }
    if (typeof salvo.contadorId === "number") contadorId = salvo.contadorId;
    return { ...dados, curtidasPorPaciente };
  } catch {
    return null;
  }
}

export const db: BancoMock = carregar() ?? sementes();

let timerGravacao: ReturnType<typeof setTimeout> | null = null;

function gravarAgora(): void {
  if (typeof localStorage === "undefined") return;
  try {
    localStorage.setItem(CHAVE_PERSISTENCIA, serializar(db));
  } catch {
    // Cota cheia ou modo privado: segue só em memória, como era antes.
  }
}

/**
 * Os repositories mutam `db` direto, e sempre depois de `await atraso(...)`.
 * Gravar no próprio `atraso` salvaria o estado *anterior* à mutação, então a
 * gravação é adiada: o timer começa quando a operação começa e dispara bem
 * depois de ela terminar. Rajadas de escrita reiniciam o timer e viram uma
 * gravação só.
 */
export function persistir(): void {
  if (typeof localStorage === "undefined") return;
  if (timerGravacao) clearTimeout(timerGravacao);
  timerGravacao = setTimeout(() => {
    timerGravacao = null;
    gravarAgora();
  }, 400);
}

if (typeof window !== "undefined") {
  // Fechar a aba no meio do debounce não pode perder o que acabou de ser feito.
  window.addEventListener("pagehide", gravarAgora);
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") gravarAgora();
  });
}

/** Volta tudo ao estado inicial — usado pelo botão de reiniciar a demonstração. */
export function reiniciarDemonstracao(): void {
  if (timerGravacao) clearTimeout(timerGravacao);
  timerGravacao = null;
  Object.assign(db, sementes());
  contadorId = 1000;
  try {
    localStorage.removeItem(CHAVE_PERSISTENCIA);
  } catch {
    // sem localStorage: o Object.assign acima já bastou
  }
}

/** Simula latência de rede — mantém as telas honestas sobre precisar de estado de carregamento (briefing §7, §18). */
export function atraso(ms = 220): Promise<void> {
  // Toda operação de repository passa por aqui; é o gatilho da gravação
  // adiada, que roda depois de a mutação já ter acontecido.
  persistir();
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export function gerarId(prefixo: string): string {
  contadorId += 1;
  return `${prefixo}-${contadorId}`;
}

export function agoraISO(): string {
  return new Date().toISOString();
}
