import type { CheckIn, CheckInRascunho } from "@/types";
import { checkinRepository } from "@/repositories";
import { avaliarOrigensDeAlerta, dispararAlertas } from "./alertaService";

export async function buscarCheckinDoDia(pacienteId: string, data: string): Promise<CheckIn | null> {
  return checkinRepository.buscarCheckinDoDia(pacienteId, data);
}

export async function buscarHistorico(pacienteId: string, dias = 14): Promise<CheckIn[]> {
  return checkinRepository.listarHistorico(pacienteId, dias);
}

/**
 * Ponto único de gravação de check-in. Decide os alertas clínicos (regra
 * determinística, briefing §22) e devolve `avisoSangue` para a tela exibir
 * o aviso institucional (Anexo §14 · Check-in) — a UI nunca decide sozinha
 * se um alerta foi gerado, só reage ao que o serviço retorna.
 */
export async function salvarCheckin(
  nutricionistaId: string,
  rascunho: CheckInRascunho,
): Promise<{ checkin: CheckIn; avisoSangue: boolean }> {
  const historicoRecente = await checkinRepository.listarHistorico(rascunho.pacienteId, 3);
  const origens = avaliarOrigensDeAlerta(rascunho, historicoRecente);
  const gerouAlertaClinico = origens.length > 0;

  const checkin = await checkinRepository.salvarCheckin(nutricionistaId, rascunho, gerouAlertaClinico);
  if (gerouAlertaClinico) {
    await dispararAlertas(nutricionistaId, rascunho.pacienteId, checkin.id, origens);
  }

  return { checkin, avisoSangue: rascunho.flags.includes("sangue") };
}
