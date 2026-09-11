import { useEffect } from "react";
import { Navigate, Route, Routes, useLocation } from "react-router-dom";
import "./styles/central.css";
import { NavPrincipal } from "./components/NavPrincipal";
import { Home } from "./pages/Home";
import { TrocaInteligente } from "./pages/TrocaInteligente";
import { Substituicoes } from "./pages/Substituicoes";
import { GrupoDetalhe } from "./pages/GrupoDetalhe";
import { ComerFora } from "./pages/ComerFora";
import { CategoriaDetalhe } from "./pages/CategoriaDetalhe";
import { Guias } from "./pages/Guias";
import { GuiaDetalhe } from "./pages/GuiaDetalhe";
import { Salvos } from "./pages/Salvos";
import { Busca } from "./pages/Busca";
import { BASE } from "./rotas";

/**
 * Central do Paciente — a casca do app.
 *
 * Monta a navegação e as rotas; nenhuma regra de negócio passa por aqui.
 * As telas ficam em `pages/`, os dados em `data/` e as contas em `utils/` —
 * essa separação é o que o briefing (§26) pede e é o que permite crescer sem
 * reescrever nada.
 */
export function CentralApp() {
  const { pathname } = useLocation();

  // Navegar entre telas deve começar no topo, como num app — sem isto o
  // celular mantém a rolagem da tela anterior e a nova parece cortada.
  useEffect(() => {
    window.scrollTo(0, 0);
  }, [pathname]);

  return (
    <div className="central">
      <div className="c-casca">
        <Routes>
          <Route index element={<Home />} />
          <Route path="trocas" element={<TrocaInteligente />} />
          <Route path="substituicoes" element={<Substituicoes />} />
          <Route path="substituicoes/:grupoId" element={<GrupoDetalhe />} />
          <Route path="comer-fora" element={<ComerFora />} />
          <Route path="comer-fora/:categoriaId" element={<CategoriaDetalhe />} />
          <Route path="guias" element={<Guias />} />
          <Route path="guias/:guiaId" element={<GuiaDetalhe />} />
          <Route path="salvos" element={<Salvos />} />
          <Route path="busca" element={<Busca />} />
          <Route path="*" element={<Navigate to={BASE} replace />} />
        </Routes>
        <NavPrincipal />
      </div>
    </div>
  );
}
