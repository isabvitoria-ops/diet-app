import { useCallback } from "react";
import type { PoseFoto } from "@/types";
import { evolucaoService } from "@/services";
import { useAsync } from "./useAsync";

export function useSessoesFoto(pacienteId: string, nutricionistaId: string) {
  const [estado, recarregar] = useAsync(() => evolucaoService.listarSessoesFoto(pacienteId), [pacienteId]);

  const salvar = useCallback(
    async (data: string, storagePathPorPose: Partial<Record<PoseFoto, string>>) => {
      await evolucaoService.salvarSessaoFoto(nutricionistaId, pacienteId, data, storagePathPorPose);
      recarregar();
    },
    [pacienteId, nutricionistaId, recarregar],
  );

  const apagar = useCallback(
    async (sessaoId: string) => {
      await evolucaoService.apagarSessaoFoto(sessaoId);
      recarregar();
    },
    [recarregar],
  );

  return { estado, salvar, apagar, recarregar };
}
