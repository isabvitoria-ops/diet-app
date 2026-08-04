import { useCallback } from "react";
import type { Paciente } from "@/types";
import { pacienteService } from "@/services";
import { useAsync } from "./useAsync";

export function usePaciente(pacienteId: string) {
  const [estado, recarregar] = useAsync(() => pacienteService.buscarPacientePorId(pacienteId), [pacienteId]);

  const atualizar = useCallback(
    async (paciente: Paciente) => {
      await pacienteService.atualizarPaciente(paciente);
      recarregar();
    },
    [recarregar],
  );

  return { estado, atualizar, recarregar };
}
