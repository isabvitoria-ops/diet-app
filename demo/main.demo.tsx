import React from "react";
import ReactDOM from "react-dom/client";
import { HashRouter } from "react-router-dom";
import { App } from "@/app/App";

/**
 * Entrada do build de demonstração. Idêntica a src/main.tsx exceto pelo
 * roteador: num HTML único servido de um caminho fixo não há servidor para
 * devolver o app quando alguém recarrega em /paciente, então a rota vive
 * no fragmento (#/paciente).
 */
ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App Roteador={HashRouter} />
  </React.StrictMode>,
);
