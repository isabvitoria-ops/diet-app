import { corBristol } from "@/constants/bristol";
import { useFichaPaciente } from "@/contexts/FichaPacienteContext";
import { useHistoricoCheckin } from "@/hooks/useCheckin";
import { pacienteService } from "@/services";
import { useAsync } from "@/hooks/useAsync";
import { useToast } from "@/hooks/useToast";

export function AbaRegistros() {
  const { paciente } = useFichaPaciente();
  const { estado } = useHistoricoCheckin(paciente.id, 14);
  const [estadoResumos] = useAsync(() => pacienteService.listarPacientesComResumo(), []);
  const avisar = useToast();

  const resumo = estadoResumos.status === "pronto" ? estadoResumos.dado.find((r) => r.paciente.id === paciente.id)?.resumo : null;
  const historico = estado.status === "pronto" ? estado.dado : [];

  return (
    <>
      <div className="card">
        <div className="eyebrow" style={{ marginBottom: 12 }}>Últimos 14 dias</div>
        {estado.status === "carregando" && <p style={{ color: "var(--ink-2)", margin: 0 }}>Carregando…</p>}
        {estado.status === "pronto" && (
          <div style={{ display: "flex", gap: 4, alignItems: "flex-end", height: 50 }}>
            {historico.map((c, i) => (
              <div
                key={i} title={c.bristol ? `Tipo ${c.bristol}` : "Sem registro"}
                style={{ flex: 1, borderRadius: 5, background: c.bristol ? corBristol(c.bristol) : "var(--line)", height: c.bristol ? 34 + Math.abs(4 - c.bristol) * 3 : 20 }}
              />
            ))}
          </div>
        )}
        <div style={{ fontSize: 13.5, color: "var(--ink-2)", marginTop: 14, lineHeight: 1.5 }}>
          Adesão de {resumo?.adesaoPercentual ?? "—"}% no período. Último check-in {resumo?.ultimoCheckinRotulo ?? "sem registro"}.
        </div>
      </div>

      <div style={{ height: 12 }} />
      <div className="card" style={{ borderLeft: "3px solid var(--sage)" }}>
        <div className="eyebrow" style={{ marginBottom: 8 }}>Preparação de consulta · última resposta</div>
        <div style={{ display: "grid", gap: 8, fontSize: 14, lineHeight: 1.5 }}>
          <div><strong>Seguiu o plano:</strong> na maior parte</div>
          <div><strong>Atrapalhou:</strong> comer fora, fome fora de hora</div>
          <div><strong>Quer melhorar:</strong> "conseguir levar marmita pelo menos 3 dias"</div>
        </div>
      </div>

      <div style={{ height: 12 }} />
      <div className="card">
        <div className="eyebrow" style={{ marginBottom: 4 }}>Preferências dentro do que você liberou</div>
        <p style={{ fontSize: 13.5, color: "var(--ink-2)", margin: "6px 0 16px", lineHeight: 1.5 }}>
          Não são desvios. É o que ela escolhe quando tem opção — útil para a próxima prescrição.
        </p>
        {[
          { slot: "Carboidrato do almoço", opcoes: [["Arroz, tipo 1, cozido", 3], ["Batata, inglesa, cozida", 7], ["Mandioca, cozida", 0]] as [string, number][] },
          { slot: "Proteína do jantar", opcoes: [["Merluza, filé, assado", 2], ["Ovo, cozido", 8], ["Carne, patinho, grelhado", 4]] as [string, number][] },
          { slot: "Fruta", opcoes: [["Banana, prata", 11], ["Mamão, papaia", 3]] as [string, number][] },
        ].map((g) => {
          const total = g.opcoes.reduce((s, o) => s + o[1], 0) || 1;
          return (
            <div key={g.slot} style={{ paddingTop: 12, borderTop: "1px solid var(--line)" }}>
              <div style={{ fontSize: 14, fontWeight: 600, marginBottom: 9 }}>{g.slot}</div>
              {g.opcoes.map(([nome, n]) => (
                <div key={nome} className="row" style={{ gap: 10, marginBottom: 7 }}>
                  <span style={{ fontSize: 13, width: 150, flexShrink: 0, color: n === 0 ? "var(--ink-3)" : "var(--ink)" }}>{nome}</span>
                  <div style={{ flex: 1, height: 8, background: "var(--paper)", borderRadius: 99 }}>
                    <div style={{ width: `${(n / total) * 100}%`, height: "100%", borderRadius: 99, background: n === 0 ? "transparent" : "var(--plum-2)" }} />
                  </div>
                  <span className="mono" style={{ fontSize: 11.5, color: "var(--ink-3)", width: 26, textAlign: "right", flexShrink: 0 }}>{n}×</span>
                </div>
              ))}
            </div>
          );
        })}
      </div>

      <div style={{ height: 12 }} />
      <div className="grid2">
        <button className="card" onClick={() => avisar("Diário alimentar completo abriria aqui.")} style={{ border: 0, cursor: "pointer", textAlign: "left", fontFamily: "inherit" }}>
          <div style={{ fontSize: 15, fontWeight: 600 }}>Diário alimentar</div>
          <div style={{ fontSize: 13, color: "var(--ink-2)", marginTop: 4 }}>Ver registros da semana</div>
        </button>
        <button className="card" onClick={() => avisar("Fotos abririam aqui, com acesso registrado em auditoria.")} style={{ border: 0, cursor: "pointer", textAlign: "left", fontFamily: "inherit" }}>
          <div style={{ fontSize: 15, fontWeight: 600 }}>Fotos de evolução</div>
          <div style={{ fontSize: 13, color: "var(--ink-2)", marginTop: 4 }}>Acesso auditado</div>
        </button>
      </div>
    </>
  );
}
