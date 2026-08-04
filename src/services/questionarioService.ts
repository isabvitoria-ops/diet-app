import type { Pergunta, QuestionarioTemplate, RespostaQuestionario } from "@/types";
import { questionarioRepository } from "@/repositories";

export async function buscarTemplateMensal(): Promise<QuestionarioTemplate | null> {
  return questionarioRepository.buscarTemplateAtivo("mensal");
}

export async function pendenteEsteMs(pacienteId: string, template: QuestionarioTemplate): Promise<boolean> {
  const jaRespondeu = await questionarioRepository.jaRespondeuNoMesAtual(pacienteId, template.id);
  return !jaRespondeu;
}

export async function enviarResposta(
  nutricionistaId: string,
  pacienteId: string,
  template: QuestionarioTemplate,
  respostas: RespostaQuestionario["respostas"],
): Promise<RespostaQuestionario> {
  return questionarioRepository.salvarResposta(nutricionistaId, pacienteId, template.id, template.versao, respostas);
}

export type FaixaIncomodo = { nome: "leve" | "moderada" | "intensa"; corId: "sage" | "gold" | "clay" };

/**
 * Faixa de incômodo — porte literal do cálculo do protótipo (`Questionario`,
 * variável `faixa`). Soma as perguntas de escala (invertendo as marcadas
 * `invertida`) e divide pela quantidade de perguntas de escala.
 */
export function calcularFaixaIncomodo(perguntas: Pergunta[], respostas: Record<string, string | number | string[]>): FaixaIncomodo {
  const escalas = perguntas.filter((p) => p.tipo === "escala");
  const soma = escalas.reduce((s, p) => {
    const v = Number(respostas[p.id] ?? 0);
    return s + (p.invertida ? 10 - v : v);
  }, 0);
  const media = escalas.length ? soma / escalas.length : 0;
  if (media <= 3) return { nome: "leve", corId: "sage" };
  if (media <= 6) return { nome: "moderada", corId: "gold" };
  return { nome: "intensa", corId: "clay" };
}
