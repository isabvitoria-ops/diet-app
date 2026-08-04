import { useCallback, useState } from "react";
import type { CheckIn, CheckInRascunho } from "@/types";
import { checkinService } from "@/services";
import { paraISODate } from "@/utils/datas";
import { useAsync } from "./useAsync";

export function useCheckin(pacienteId: string) {
  const hojeISO = paraISODate(new Date());
  const [estado, recarregar] = useAsync(() => checkinService.buscarCheckinDoDia(pacienteId, hojeISO), [pacienteId, hojeISO]);
  const [salvando, setSalvando] = useState(false);

  const salvar = useCallback(
    async (nutricionistaId: string, dados: Omit<CheckInRascunho, "pacienteId" | "data" | "chaveIdempotente">) => {
      setSalvando(true);
      try {
        const rascunho: CheckInRascunho = {
          ...dados,
          pacienteId,
          data: hojeISO,
          chaveIdempotente: `${pacienteId}-${hojeISO}`,
        };
        const resultado = await checkinService.salvarCheckin(nutricionistaId, rascunho);
        recarregar();
        return resultado;
      } finally {
        setSalvando(false);
      }
    },
    [pacienteId, hojeISO, recarregar],
  );

  return { estado, salvando, salvar, recarregar };
}

export function useHistoricoCheckin(pacienteId: string, dias = 14) {
  const [estado, recarregar] = useAsync(() => checkinService.buscarHistorico(pacienteId, dias), [pacienteId, dias]);
  return { estado, recarregar };
}

export type { CheckIn };
