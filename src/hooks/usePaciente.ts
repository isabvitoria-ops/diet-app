import { useCallback, useEffect, useMemo, useState } from "react";
import type { Estado, Paciente } from "@/types";
import { pacienteService } from "@/services";
import { useAsync } from "./useAsync";

export function usePaciente(pacienteId: string) {
  const [estadoServidor, recarregar] = useAsync(() => pacienteService.buscarPacientePorId(pacienteId), [pacienteId]);
  const [override, setOverride] = useState<Paciente | null>(null);

  useEffect(() => {
    setOverride(null);
  }, [pacienteId]);

  const estado: Estado<Paciente | null> = useMemo(() => {
    if (override) return { status: "pronto", dado: override };
    return estadoServidor;
  }, [override, estadoServidor]);

  const atualizar = useCallback(
    async (paciente: Paciente) => {
      // Atualiza a tela na hora — a gravação já aconteceu (ou está
      // acontecendo) no service; não há por que voltar pra "carregando" e
      // fazer as 6 abas da ficha piscarem por causa de um switch.
      setOverride(paciente);
      await pacienteService.atualizarPaciente(paciente);
    },
    [],
  );

  return { estado, atualizar, recarregar };
}
