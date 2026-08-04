import React from "react";
import ReactDOM from "react-dom/client";
import { AppNutri } from "@/app/nutricionista/AppNutri";
import { NUTRICIONISTA_ID } from "@/data/mocks/ids";

/**
 * Entrada temporária enquanto a rota real (React Router + auth) não está
 * plugada (tarefa em andamento). TEMP: verificação visual do painel.
 */
ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <AppNutri nutricionistaId={NUTRICIONISTA_ID} />
  </React.StrictMode>,
);
