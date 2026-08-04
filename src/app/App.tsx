import { Suspense, lazy } from "react";
import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import "@/styles/global.css";
import { useAuth } from "@/hooks/useAuth";
import { Login } from "./Login";
import { Mfa } from "./Mfa";
import { NUTRICIONISTA_ID } from "@/data/mocks/ids";

// Performance (briefing §17): paciente e nutricionista nunca usam o app um
// do outro na mesma sessão — cada bundle só baixa o que a sua tela precisa
// em vez de carregar os dois de largada.
const AppPaciente = lazy(() => import("./paciente/AppPaciente").then((m) => ({ default: m.AppPaciente })));
const AppNutri = lazy(() => import("./nutricionista/AppNutri").then((m) => ({ default: m.AppNutri })));

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
      <Suspense fallback={<Carregando />}>
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
      </Suspense>
    </BrowserRouter>
  );
}
