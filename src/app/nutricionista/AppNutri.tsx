import "@/styles/global.css";
import { useState } from "react";
import { Toast } from "@/components/ui/Toast";
import { Dashboard } from "@/components/nutri/Dashboard";
import { ListaPacientes } from "@/components/nutri/ListaPacientes";
import { PainelBase } from "@/components/nutri/PainelBase";
import { PainelFeed } from "@/components/nutri/PainelFeed";
import { PainelBiblioteca } from "@/components/nutri/PainelBiblioteca";
import { FichaPaciente } from "@/components/nutri/ficha/FichaPaciente";
import { useContagemAtivos } from "@/hooks/usePacientes";
import { useSair } from "@/hooks/useAuth";
import { demonstracaoService } from "@/services";

type Secao = "dashboard" | "pacientes" | "base" | "feed" | "biblioteca";
const SECOES: [Secao, string][] = [
  ["dashboard", "Dashboard"], ["pacientes", "Pacientes"], ["base", "Base"], ["feed", "Feed"], ["biblioteca", "Biblioteca"],
];

export function AppNutri({ nutricionistaId }: { nutricionistaId: string }) {
  const [secao, setSecao] = useState<Secao>("dashboard");
  const [abertoId, setAbertoId] = useState<string | null>(null);
  const [confirmandoSaida, setConfirmandoSaida] = useState(false);
  const [confirmandoReinicio, setConfirmandoReinicio] = useState(false);
  const [reiniciando, setReiniciando] = useState(false);
  const ativos = useContagemAtivos();
  const sair = useSair();

  const reiniciarDemo = async () => {
    setReiniciando(true);
    await demonstracaoService.reiniciarDemonstracao();
    // As telas guardam o que já buscaram em estado do React, que o reset não
    // alcança — recarregar é o jeito honesto de voltar tudo ao início.
    window.location.reload();
  };

  const irPara = (s: Secao) => {
    setSecao(s);
    setAbertoId(null);
  };
  const abrirPaciente = (id: string) => setAbertoId(id);

  return (
    <div className="root">
      <nav className="nav">
        <div className="navin">
          <div className="disp" style={{ fontSize: 17, fontWeight: 700, marginRight: 8 }}>Painel</div>
          {SECOES.map(([id, l]) => (
            <button key={id} className={`seg ${secao === id && !abertoId ? "on" : ""}`} onClick={() => irPara(id)}>{l}</button>
          ))}
          <div style={{ flex: 1 }} />
          <div className="mono" style={{ fontSize: 11, color: "var(--ink-3)" }}>{ativos ?? "…"} ATIVOS</div>
          {/*
            Aqui sair pesa mais que no app da paciente: esta tela mostra o
            dado clínico de todas elas e costuma ficar aberta no consultório.
            Por isso o botão fica sempre à vista, não escondido num menu.
          */}
          <button
            className="seg" onClick={() => setConfirmandoSaida(true)}
            style={{ marginLeft: 12 }}
          >
            Sair
          </button>
          {/*
            Afordância da demonstração, não do produto — daí o tratamento
            apagado, separado dos controles de verdade.
          */}
          <button
            onClick={() => setConfirmandoReinicio(true)}
            title="Apaga tudo o que foi feito nesta demonstração e volta aos dados iniciais"
            style={{ marginLeft: 8, background: "none", border: 0, padding: "6px 4px", color: "var(--ink-3)", fontSize: 11, fontFamily: "'IBM Plex Mono',monospace", cursor: "pointer", textDecoration: "underline", textUnderlineOffset: 3 }}
          >
            reiniciar demo
          </button>
        </div>
      </nav>

      {confirmandoSaida && (
        <div
          onClick={(e) => e.target === e.currentTarget && setConfirmandoSaida(false)}
          style={{ position: "fixed", inset: 0, zIndex: 60, background: "rgba(26,22,25,.45)", display: "grid", placeItems: "center", padding: 18 }}
        >
          <div role="dialog" aria-modal="true" aria-labelledby="titulo-sair" className="card" style={{ width: "100%", maxWidth: 400, padding: 24 }}>
            <h2 id="titulo-sair" className="disp" style={{ fontSize: 21, fontWeight: 600, margin: "0 0 8px" }}>Sair da conta?</h2>
            <p style={{ fontSize: 14, color: "var(--ink-2)", margin: "0 0 20px", lineHeight: 1.5 }}>
              Você vai precisar do e-mail, da senha e do código de verificação para entrar de novo, a não ser que este aparelho esteja marcado como confiável.
            </p>
            <div className="row">
              <button className="btn danger" onClick={() => void sair()}>Sair</button>
              <button className="btn ghost" onClick={() => setConfirmandoSaida(false)}>Cancelar</button>
            </div>
          </div>
        </div>
      )}

      {confirmandoReinicio && (
        <div
          onClick={(e) => e.target === e.currentTarget && !reiniciando && setConfirmandoReinicio(false)}
          style={{ position: "fixed", inset: 0, zIndex: 60, background: "rgba(26,22,25,.45)", display: "grid", placeItems: "center", padding: 18 }}
        >
          <div role="dialog" aria-modal="true" aria-labelledby="titulo-reiniciar" className="card" style={{ width: "100%", maxWidth: 430, padding: 24 }}>
            <h2 id="titulo-reiniciar" className="disp" style={{ fontSize: 21, fontWeight: 600, margin: "0 0 8px" }}>Reiniciar a demonstração?</h2>
            <p style={{ fontSize: 14, color: "var(--ink-2)", margin: "0 0 8px", lineHeight: 1.5 }}>
              Apaga tudo o que foi feito aqui — planos publicados, pacientes convidadas, check-ins, fotos, posts e mensagens — e devolve os dados de exemplo do início.
            </p>
            <p style={{ fontSize: 13.5, color: "var(--ink-3)", margin: "0 0 20px", lineHeight: 1.5 }}>
              Você sai da conta e o código de verificação volta a ser pedido. Não tem como desfazer.
            </p>
            <div className="row">
              <button className="btn danger" onClick={() => void reiniciarDemo()} disabled={reiniciando}>
                {reiniciando ? "Reiniciando…" : "Apagar e recomeçar"}
              </button>
              <button className="btn ghost" onClick={() => setConfirmandoReinicio(false)} disabled={reiniciando}>Cancelar</button>
            </div>
          </div>
        </div>
      )}

      {abertoId ? (
        <FichaPaciente pacienteId={abertoId} nutricionistaId={nutricionistaId} voltar={() => setAbertoId(null)} />
      ) : (
        <>
          {secao === "dashboard" && <Dashboard nutricionistaId={nutricionistaId} abrirPaciente={abrirPaciente} />}
          {secao === "pacientes" && <ListaPacientes nutricionistaId={nutricionistaId} abrir={abrirPaciente} />}
          {secao === "base" && <PainelBase />}
          {secao === "feed" && <PainelFeed nutricionistaId={nutricionistaId} />}
          {secao === "biblioteca" && <PainelBiblioteca />}
        </>
      )}

      <Toast />
    </div>
  );
}
