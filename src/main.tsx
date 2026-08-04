import React from "react";
import ReactDOM from "react-dom/client";
import { AppPaciente } from "@/app/paciente/AppPaciente";
import { PACIENTE_MARINA_ID, NUTRICIONISTA_ID } from "@/data/mocks/ids";

/**
 * Entrada temporária enquanto a rota real (React Router + auth) não está
 * plugada (tarefa em andamento). Sobe direto o app do paciente com Marina
 * só para validar a pilha de ponta a ponta.
 */
ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <AppPaciente pacienteId={PACIENTE_MARINA_ID} nutricionistaId={NUTRICIONISTA_ID} />
  </React.StrictMode>,
);
