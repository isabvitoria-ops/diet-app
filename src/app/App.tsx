import { Suspense, lazy } from "react";
import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import "@/styles/global.css";
import { useAuth } from "@/hooks/useAuth";
import { Login } from "./Login";
import { Mfa } from "./Mfa";
import { NUTRICIONISTA_ID } from "@/data/mocks/ids";

// Performance (briefing §17): paciente e nutricionista nunca usam o app um
// do outro na mesma sessão — cada bundle só baixa o que a sua tela precisa
// em vez de carregar os dois de largada. A Central do Paciente entra na
// mesma regra: quem faz login no acompanhamento não baixa o bundle dela.
const AppPaciente = lazy(() => import("./paciente/AppPaciente").then((m) => ({ default: m.AppPaciente })));
const AppNutri = lazy(() => import("./nutricionista/AppNutri").then((m) => ({ default: m.AppNutri })));
const CentralApp = lazy(() => import("@/central/CentralApp").then((m) => ({ default: m.CentralApp })));

function Carregando() {
  return (
    <div style={{ minHeight: "100vh", display: "grid", placeItems: "center", background: "var(--paper)", color: "var(--ink-2)", fontFamily: "system-ui" }}>
      Carregando…
    </div>
  );
}

/**
 * Roteamento de topo: `/central/*` (aberto) e todo o resto (autenticado).
 *
 * A Central do Paciente é uma ferramenta de consulta — troca de alimentos,
 * comer fora, guias — e não toca em dado clínico de ninguém, então fica
 * fora do portão de login: o paciente abre o link e usa. O acompanhamento
 * (`/paciente`, `/nutricionista`) continua exigindo sessão exatamente como
 * antes; o que mudou foi só a ordem — o `BrowserRouter` agora envolve o
 * portão em vez de ficar depois dele.
 */
export function App() {
  return (
    <BrowserRouter>
      <Suspense fallback={<Carregando />}>
        <Routes>
          <Route path="/central/*" element={<CentralApp />} />
          <Route path="/*" element={<AppAutenticado />} />
        </Routes>
      </Suspense>
    </BrowserRouter>
  );
}

/**
 * Single-tenant (briefing §3, §21): hoje só existe uma nutricionista, então
 * o app do paciente aponta direto para `NUTRICIONISTA_ID` em vez de
 * resolver dinamicamente — isso muda no dia em que houver mais de uma conta.
 */
function AppAutenticado() {
  const { sessao, carregando, aguardandoMfa } = useAuth();

  if (carregando) return <Carregando />;
  if (aguardandoMfa) return <Mfa />;
  if (!sessao) return <Login />;

  return (
    <Routes>
      {sessao.papel === "paciente" && (
        <>
          <Route path="paciente/*" element={<AppPaciente pacienteId={sessao.perfilId} nutricionistaId={NUTRICIONISTA_ID} />} />
          <Route path="*" element={<Navigate to="/paciente" replace />} />
        </>
      )}
      {sessao.papel === "nutricionista" && (
        <>
          <Route path="nutricionista/*" element={<AppNutri nutricionistaId={sessao.perfilId} />} />
          <Route path="*" element={<Navigate to="/nutricionista" replace />} />
        </>
      )}
    </Routes>
  );
}
