import type { Paciente, ResumoAdesaoPaciente } from "@/types";
import { pacienteRepository } from "@/repositories";
import type { DadosConvite } from "@/repositories/pacienteRepository";
import { chaves, invalidar } from "@/store/revalidacaoStore";

export interface PacienteComResumo {
  paciente: Paciente;
  resumo: ResumoAdesaoPaciente | null;
}

/** Erros de preenchimento por campo — vazio quer dizer "pode enviar". */
export type ErrosConvite = Partial<Record<"nome" | "email" | "objetivo", string>>;

export function validarConvite(dados: DadosConvite): ErrosConvite {
  const erros: ErrosConvite = {};
  if (!dados.nome.trim()) erros.nome = "Informe o nome da paciente.";

  const email = dados.email.trim();
  if (!email) erros.email = "O e-mail é como ela entra no app.";
  else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) erros.email = "Este e-mail não parece válido.";

  if (!dados.objetivo.trim()) erros.objetivo = "Informe o objetivo do acompanhamento.";
  return erros;
}

/**
 * Regra #14: acesso só por convite. A validação vive aqui (não na tela) para
 * valer também quando o convite vier de outro lugar.
 */
export async function convidarPaciente(nutricionistaId: string, dados: DadosConvite): Promise<Paciente> {
  const erros = validarConvite(dados);
  const primeiro = Object.values(erros)[0];
  if (primeiro) throw new Error(primeiro);
  const paciente = await pacienteRepository.convidarPaciente(nutricionistaId, dados);
  invalidar(chaves.pacientes());
  return paciente;
}

export async function listarPacientesComResumo(): Promise<PacienteComResumo[]> {
  const [pacientes, resumos] = await Promise.all([
    pacienteRepository.listarPacientes(),
    pacienteRepository.listarResumosAdesao(),
  ]);
  const resumoPorId = new Map(resumos.map((r) => [r.pacienteId, r]));
  return pacientes.map((paciente) => ({ paciente, resumo: resumoPorId.get(paciente.id) ?? null }));
}

export async function buscarPacientePorId(id: string): Promise<Paciente | null> {
  return pacienteRepository.buscarPacientePorId(id);
}

export async function atualizarPaciente(paciente: Paciente): Promise<Paciente> {
  return pacienteRepository.atualizarPaciente(paciente);
}

/** Regra #8: reversível a qualquer momento, nunca apaga dado. */
export async function definirAcessoAtivo(pacienteId: string, ativo: boolean): Promise<Paciente> {
  const paciente = await pacienteRepository.definirAcessoAtivo(pacienteId, ativo);
  // Muda a contagem de ativas: a lista e o cabeçalho precisam saber.
  invalidar(chaves.pacientes());
  return paciente;
}

export function filtrarPacientes(
  itens: PacienteComResumo[],
  busca: string,
  incluirInativos: boolean,
): PacienteComResumo[] {
  const buscaLower = busca.trim().toLowerCase();
  return itens
    .filter(({ paciente }) => incluirInativos || paciente.ativo)
    .filter(({ paciente }) => paciente.nome.toLowerCase().includes(buscaLower));
}
