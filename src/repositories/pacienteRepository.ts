import type { Paciente, ResumoAdesaoPaciente, UnidadeExibicao } from "@/types";
import { agoraISO, atraso, db, gerarId } from "./mockDb";

/**
 * Uma função por operação, como pede o briefing §8. Hoje lê/escreve em
 * `mockDb`; trocar por Supabase significa reescrever só o corpo destas
 * funções — a assinatura e o retorno (Promise) já são os mesmos.
 */
export async function listarPacientes(): Promise<Paciente[]> {
  await atraso();
  return db.pacientes;
}

export async function buscarPacientePorId(id: string): Promise<Paciente | null> {
  await atraso();
  return db.pacientes.find((p) => p.id === id) ?? null;
}

export async function listarResumosAdesao(): Promise<ResumoAdesaoPaciente[]> {
  await atraso();
  return db.resumosAdesao;
}

export interface DadosConvite {
  nome: string;
  email: string;
  objetivo: string;
  preferenciaUnidade: UnidadeExibicao;
  pesoModoCego: boolean;
}

/**
 * Próximo apelido livre do feed. É o número por trás do qual o paciente
 * aparece para os outros (regra §13: ninguém tem nome nem foto no feed), então
 * não pode repetir — dois "021" seriam duas pessoas diferentes com a mesma
 * identidade pública.
 */
function proximoApelidoFeed(): string {
  const usados = new Set(db.pacientes.map((p) => p.apelidoFeed));
  const maior = db.pacientes.reduce((m, p) => Math.max(m, Number(p.apelidoFeed) || 0), 0);
  let n = maior + 1;
  while (usados.has(String(n).padStart(3, "0"))) n += 1;
  return String(n).padStart(3, "0");
}

/**
 * Regra #14: não existe cadastro público — a nutricionista convida. O
 * paciente nasce ativo e sem nada liberado: os alimentos (regra #1) e os
 * materiais são escolhas dela, feitas depois nas abas da ficha.
 */
export async function convidarPaciente(nutricionistaId: string, dados: DadosConvite): Promise<Paciente> {
  await atraso(300);
  const email = dados.email.trim().toLowerCase();
  if (db.pacientes.some((p) => p.email.toLowerCase() === email)) {
    throw new Error("Já existe uma paciente com este e-mail.");
  }
  const paciente: Paciente = {
    id: gerarId("paciente"),
    nutricionistaId,
    criadoEm: agoraISO(),
    atualizadoEm: agoraISO(),
    nome: dados.nome.trim(),
    apelidoFeed: proximoApelidoFeed(),
    email,
    objetivo: dados.objetivo.trim(),
    ativo: true,
    convidadoEm: agoraISO(),
    ultimoLoginEm: null,
    alimentosLiberadosCodigoTaco: [],
    materiaisLiberadosId: [],
    preferenciaUnidade: dados.preferenciaUnidade,
    pesoModoCego: dados.pesoModoCego,
  };
  db.pacientes.push(paciente);
  return paciente;
}

export async function atualizarPaciente(paciente: Paciente): Promise<Paciente> {
  await atraso();
  const i = db.pacientes.findIndex((p) => p.id === paciente.id);
  if (i === -1) throw new Error(`Paciente ${paciente.id} não encontrado`);
  const atualizado = { ...paciente, atualizadoEm: agoraISO() };
  db.pacientes[i] = atualizado;
  return atualizado;
}

/** Regra #8: encerrar acesso nunca apaga dado — só alterna `ativo`, reversível a qualquer momento. */
export async function definirAcessoAtivo(pacienteId: string, ativo: boolean): Promise<Paciente> {
  const paciente = await buscarPacientePorId(pacienteId);
  if (!paciente) throw new Error(`Paciente ${pacienteId} não encontrado`);
  return atualizarPaciente({ ...paciente, ativo });
}
