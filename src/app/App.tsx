import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import "@/styles/global.css";
import { useAuth } from "@/hooks/useAuth";
import { Login } from "./Login";
import { Mfa } from "./Mfa";
import { AppPaciente } from "./paciente/AppPaciente";
import { AppNutri } from "./nutricionista/AppNutri";
import { NUTRICIONISTA_ID } from "@/data/mocks/ids";

function Carregando() {
  return (
    <div style={{ minHeight: "100vh", display: "grid", placeItems: "center", background: "var(--paper)", color: "var(--ink-2)", fontFamily: "system-ui" }}>
      Carregando…
    </div>
  );
}

/**
 * Roteamento de topo (briefing §8): /login, /paciente/*, /nutricionista/*.
 * Cada app continua gerenciando a navegação entre suas próprias telas por
 * estado interno (abas) — não há necessidade de sub-rotas por tela aqui.
 *
 * Single-tenant (briefing §3, §21): hoje só existe uma nutricionista, então
 * o app do paciente aponta direto para `NUTRICIONISTA_ID` em vez de
 * resolver dinamicamente — isso muda no dia em que houver mais de uma conta.
 */
export function App() {
  const { sessao, carregando, aguardandoMfa } = useAuth();

  if (carregando) return <Carregando />;
  if (aguardandoMfa) return <Mfa />;
  if (!sessao) return <Login />;

  return (
    <BrowserRouter>
      <Routes>
        {sessao.papel === "paciente" && (
          <>
            <Route path="/paciente/*" element={<AppPaciente pacienteId={sessao.perfilId} nutricionistaId={NUTRICIONISTA_ID} />} />
            <Route path="*" element={<Navigate to="/paciente" replace />} />
          </>
        )}
        {sessao.papel === "nutricionista" && (
          <>
            <Route path="/nutricionista/*" element={<AppNutri nutricionistaId={sessao.perfilId} />} />
            <Route path="*" element={<Navigate to="/nutricionista" replace />} />
          </>
        )}
      </Routes>
    </BrowserRouter>
  );
}
