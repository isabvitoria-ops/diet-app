import { createContext, useContext, useState, type ReactNode } from "react";
import type { Paciente } from "@/types";

/**
 * Escopo naturalmente hierárquico (briefing §9): a ficha de um paciente
 * aberta no painel. Evita passar `paciente`/`atualizar` manualmente por
 * cada uma das seis abas (Plano, Alimentos, Equivalências, Materiais,
 * Registros, Acesso) — cada aba só chama `useFichaPaciente()`.
 */
interface FichaPacienteContextValue {
  paciente: Paciente;
  atualizar: (paciente: Paciente) => void;
}

const FichaPacienteContext = createContext<FichaPacienteContextValue | null>(null);

export function FichaPacienteProvider({
  pacienteInicial,
  onAtualizar,
  children,
}: {
  pacienteInicial: Paciente;
  onAtualizar?: (paciente: Paciente) => void;
  children: ReactNode;
}) {
  const [paciente, setPaciente] = useState(pacienteInicial);

  const atualizar = (novo: Paciente) => {
    setPaciente(novo);
    onAtualizar?.(novo);
  };

  return <FichaPacienteContext.Provider value={{ paciente, atualizar }}>{children}</FichaPacienteContext.Provider>;
}

export function useFichaPaciente(): FichaPacienteContextValue {
  const ctx = useContext(FichaPacienteContext);
  if (!ctx) throw new Error("useFichaPaciente precisa estar dentro de <FichaPacienteProvider>");
  return ctx;
}
