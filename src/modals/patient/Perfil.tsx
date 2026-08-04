import { useState } from "react";
import { Sheet } from "@/components/ui/Sheet";
import { Btn } from "@/components/ui/Button";
import { useSair } from "@/hooks/useAuth";
import type { Paciente } from "@/types";

export type DestinoPerfil = "biblioteca" | "questionario" | "lembretes" | "privacidade";

export function Perfil({
  paciente,
  questionarioPendente,
  onFechar,
  abrir,
}: {
  paciente: Paciente;
  questionarioPendente: boolean;
  onFechar: () => void;
  abrir: (destino: DestinoPerfil) => void;
}) {
  const sair = useSair();
  const [confirmandoSaida, setConfirmandoSaida] = useState(false);

  const itens: [DestinoPerfil, string, string][] = [
    ["biblioteca", "Biblioteca", "Artigos, receitas e aulas rápidas"],
    ["questionario", "Questionário mensal", questionarioPendente ? "Pendente — leva 2 minutos" : "Respondido este mês"],
    ["lembretes", "Lembretes", "Quando e como o app fala com você"],
    ["privacidade", "Meus dados", "Exportar, corrigir ou apagar"],
  ];

  return (
    <Sheet onFechar={onFechar} titulo="Meu perfil">
      <div style={{ display: "flex", alignItems: "center", gap: 14, marginBottom: 24 }}>
        <div style={{ width: 52, height: 52, borderRadius: 17, background: "var(--plum-wash)", display: "grid", placeItems: "center", color: "var(--plum)", fontFamily: "'IBM Plex Mono',monospace", fontSize: 15 }}>
          {paciente.apelidoFeed}
        </div>
        <div>
          <div className="disp" style={{ fontSize: 21, fontWeight: 600 }}>{paciente.nome.split(" ")[0]}</div>
          <div style={{ fontSize: 13.5, color: "var(--ink-2)", marginTop: 2 }}>
            {paciente.faseRotulo ?? "Sem fase definida"} · no feed você é Paciente {paciente.apelidoFeed}
          </div>
        </div>
      </div>

      <div style={{ display: "grid", gap: 8 }}>
        {itens.map(([id, t, d]) => (
          <button
            key={id} onClick={() => abrir(id)} className="card"
            style={{ border: 0, cursor: "pointer", textAlign: "left", width: "100%", fontFamily: "inherit", display: "flex", alignItems: "center", gap: 12 }}
          >
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 15.5, fontWeight: 600 }}>{t}</div>
              <div style={{ fontSize: 13, color: id === "questionario" && questionarioPendente ? "var(--gold)" : "var(--ink-2)", marginTop: 3 }}>{d}</div>
            </div>
            <span style={{ color: "var(--plum)", fontSize: 18 }}>→</span>
          </button>
        ))}
      </div>

      <p style={{ fontSize: 13, color: "var(--ink-3)", lineHeight: 1.55, margin: "22px 0 0" }}>
        Seus registros pertencem a você. A qualquer momento dá para pedir uma cópia de tudo ou apagar sua conta — e sua nutri é avisada quando isso acontece.
      </p>
      <Btn variante="ghost" style={{ marginTop: 20 }} onClick={onFechar}>Fechar</Btn>

      {/*
        A sessão é persistente de propósito (§5): ninguém digita senha todo
        dia. Sair é a exceção — fica discreto, no fim, e pede confirmação,
        porque voltar custa o e-mail e a senha de novo.
      */}
      <div style={{ borderTop: "1px solid var(--line)", marginTop: 22, paddingTop: 18 }}>
        {!confirmandoSaida ? (
          <button
            type="button" onClick={() => setConfirmandoSaida(true)}
            style={{ width: "100%", background: "none", border: 0, padding: "6px 0", color: "var(--ink-3)", fontSize: 14, cursor: "pointer", fontFamily: "inherit" }}
          >
            Sair da conta
          </button>
        ) : (
          <>
            <p style={{ fontSize: 13.5, color: "var(--ink-2)", margin: "0 0 14px", lineHeight: 1.5, textAlign: "center" }}>
              Você vai precisar do seu e-mail e senha para entrar de novo. Seus registros continuam salvos.
            </p>
            <div style={{ display: "flex", gap: 10 }}>
              <Btn variante="ghost" style={{ flex: 1 }} onClick={() => setConfirmandoSaida(false)}>Ficar</Btn>
              <button
                type="button" onClick={() => void sair()}
                style={{ flex: 1, padding: "14px 0", borderRadius: 14, border: 0, background: "var(--clay)", color: "#fff", fontSize: 15, fontWeight: 500, cursor: "pointer", fontFamily: "inherit" }}
              >
                Sair
              </button>
            </div>
          </>
        )}
      </div>
    </Sheet>
  );
}
