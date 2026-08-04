import { atraso, db } from "./mockDb";

/**
 * Regra §5 (exceção deliberada): sessão persistente não isenta a
 * nutricionista de MFA no primeiro login em cada dispositivo novo. Uma vez
 * confiado, o dispositivo fica confiável por 90 dias — depois disso pede
 * o código de novo, mesmo com a sessão ainda válida.
 */
const DIAS_CONFIANCA = 90;

export async function dispositivoEhConfiavel(deviceId: string): Promise<boolean> {
  await atraso(80);
  const entrada = db.nutricionista.dispositivosConfiaveis.find((d) => d.deviceId === deviceId);
  if (!entrada) return false;
  return new Date(entrada.confiadoAte).getTime() > Date.now();
}

export async function confiarDispositivo(deviceId: string): Promise<void> {
  await atraso(150);
  const confiadoAte = new Date(Date.now() + DIAS_CONFIANCA * 24 * 60 * 60 * 1000).toISOString();
  const existente = db.nutricionista.dispositivosConfiaveis.find((d) => d.deviceId === deviceId);
  if (existente) existente.confiadoAte = confiadoAte;
  else db.nutricionista.dispositivosConfiaveis.push({ deviceId, confiadoAte });
}
