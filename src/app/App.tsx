import { Suspense, lazy } from "react";
import { BrowserRouter, HashRouter, Navigate, Route, Routes, useLocation } from "react-router-dom";
import "@/central/styles/central.css";
import { ProvedorSessao } from "@/central/autenticacao/SessaoContexto";
import { Carregando, ExigeAcesso, ExigeAdmin, ExigeSessao } from "@/central/autenticacao/Protegido";
import { Entrar } from "@/central/autenticacao/Entrar";
import { DefinirSenha } from "@/central/autenticacao/DefinirSenha";
import { RecuperarSenha } from "@/central/autenticacao/RecuperarSenha";
import { SemAcesso } from "@/central/autenticacao/SemAcesso";
import { PREFIXO_ANTIGO, rotas } from "@/central/rotas";

// Cada área baixa só o que precisa: quem é paciente nunca carrega o pacote
// da área da nutricionista, e vice-versa.
const CentralApp = lazy(() => import("@/central/CentralApp").then((m) => ({ default: m.CentralApp })));
const AdminApp = lazy(() => import("@/central/admin/AdminApp").then((m) => ({ default: m.AdminApp })));
const Consultorio = lazy(() => import("./Consultorio").then((m) => ({ default: m.Consultorio })));

/**
 * Roteamento de topo.
 *
 *   /                 Central do paciente — exige acesso liberado
 *   /entrar           entrada, também usada pelo convite
 *   /definir-senha    onde o link do e-mail cai
 *   /sem-acesso       expirado, suspenso ou ainda não liberado
 *   /admin            área da nutricionista
 *   /central/...      redireciona para o caminho novo (links já enviados)
 *   /consultorio      app antigo de acompanhamento, desligado por padrão
 *
 * Os portões daqui (`ExigeAcesso`, `ExigeAdmin`) servem para levar a pessoa
 * à tela certa. Quem de fato protege o conteúdo é a política de acesso do
 * banco — ver supabase/migracoes/0003_rls.sql.
 */
/**
 * Em produção as rotas são endereços normais (`/trocas`), que é o que se
 * quer num link enviado para paciente. O build de demonstração usa rotas por
 * hash (`#/trocas`) porque ele é servido por um host estático que não sabe
 * devolver o index.html para um caminho que não existe como arquivo.
 */
const Roteador = import.meta.env.VITE_ROTEADOR === "hash" ? HashRouter : BrowserRouter;

export function App() {
  // O app antigo de acompanhamento (login de teste, dados fictícios em
  // memória) continua no repositório, mas fica fora do ar por padrão: ele
  // aceita qualquer senha e mostra pacientes inventados, o que não pode
  // aparecer num endereço que pacientes de verdade vão acessar. Para usar em
  // desenvolvimento, defina VITE_APP_ANTIGO=1 no .env.local.
  const mostrarAppAntigo = import.meta.env.VITE_APP_ANTIGO === "1";

  return (
    <Roteador>
      <ProvedorSessao>
        <Suspense fallback={<Carregando />}>
          <Routes>
            <Route path={rotas.entrar} element={<Entrar />} />
            <Route path={rotas.definirSenha} element={<DefinirSenha />} />
            <Route path={rotas.recuperarSenha} element={<RecuperarSenha />} />
            <Route
              path={rotas.semAcesso}
              element={
                <ExigeSessao>
                  <SemAcesso />
                </ExigeSessao>
              }
            />
            <Route
              path="/admin/*"
              element={
                <ExigeAdmin>
                  <AdminApp />
                </ExigeAdmin>
              }
            />
            <Route path={`${PREFIXO_ANTIGO}/*`} element={<RedirecionaPrefixoAntigo />} />
            {mostrarAppAntigo && <Route path="/consultorio/*" element={<Consultorio />} />}
            <Route
              path="/*"
              element={
                <ExigeAcesso>
                  <CentralApp />
                </ExigeAcesso>
              }
            />
          </Routes>
        </Suspense>
      </ProvedorSessao>
    </Roteador>
  );
}

/** A Central morava em /central; links já enviados continuam funcionando. */
function RedirecionaPrefixoAntigo() {
  const { pathname, search } = useLocation();
  const destino = pathname.slice(PREFIXO_ANTIGO.length) || "/";
  return <Navigate to={`${destino}${search}`} replace />;
}
