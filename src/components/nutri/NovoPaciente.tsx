import { useEffect, useRef, useState } from "react";
import { pacienteService } from "@/services";
import type { ErrosConvite } from "@/services/pacienteService";
import type { Paciente, UnidadeExibicao } from "@/types";

const OBJETIVOS = ["Saúde intestinal", "Emagrecimento", "Hipertrofia", "Constipação"];

/**
 * Convite de paciente (regra #14: não existe cadastro público — quem cria a
 * conta é a nutricionista).
 *
 * Pede só o que não dá para inferir. O apelido do feed é gerado no
 * repositório, e alimentos e materiais nascem vazios de propósito: liberar é
 * decisão dela (regra #1), tomada nas abas da ficha com a base à vista, não
 * num campo de cadastro.
 *
 * O painel não tinha padrão de modal; este é montado com as mesmas classes do
 * resto (`card`, `input`, `btn`, `chip`) para não introduzir uma linguagem
 * visual nova.
 */
export function NovoPaciente({
  nutricionistaId,
  onFechar,
  onCriado,
}: {
  nutricionistaId: string;
  onFechar: () => void;
  onCriado: (paciente: Paciente) => void;
}) {
  const [nome, setNome] = useState("");
  const [email, setEmail] = useState("");
  const [objetivo, setObjetivo] = useState(OBJETIVOS[0]!);
  const [preferenciaUnidade, setPreferenciaUnidade] = useState<UnidadeExibicao>("g");
  const [pesoModoCego, setPesoModoCego] = useState(false);
  const [erros, setErros] = useState<ErrosConvite>({});
  const [erroEnvio, setErroEnvio] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);
  const painel = useRef<HTMLDivElement>(null);
  const primeiroCampo = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const focadoAntes = document.activeElement as HTMLElement | null;
    primeiroCampo.current?.focus();

    const aoTeclar = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        onFechar();
        return;
      }
      if (e.key !== "Tab") return;
      const alvos = Array.from(
        painel.current?.querySelectorAll<HTMLElement>(
          'a[href], button:not([disabled]), textarea, input:not([disabled]), select, [tabindex]:not([tabindex="-1"])',
        ) ?? [],
      ).filter((el) => el.offsetParent !== null);
      if (alvos.length === 0) return;
      const primeiro = alvos[0]!;
      const ultimo = alvos[alvos.length - 1]!;
      if (e.shiftKey && document.activeElement === primeiro) {
        e.preventDefault();
        ultimo.focus();
      } else if (!e.shiftKey && document.activeElement === ultimo) {
        e.preventDefault();
        primeiro.focus();
      }
    };

    document.addEventListener("keydown", aoTeclar);
    return () => {
      document.removeEventListener("keydown", aoTeclar);
      focadoAntes?.focus?.();
    };
  }, [onFechar]);

  const enviar = async () => {
    const dados = { nome, email, objetivo, preferenciaUnidade, pesoModoCego };
    const encontrados = pacienteService.validarConvite(dados);
    setErros(encontrados);
    setErroEnvio(null);
    if (Object.keys(encontrados).length > 0) return;

    setEnviando(true);
    try {
      onCriado(await pacienteService.convidarPaciente(nutricionistaId, dados));
    } catch (e) {
      // E-mail repetido só aparece aqui: quem sabe é o repositório.
      setErroEnvio(e instanceof Error ? e.message : "Não foi possível enviar o convite.");
    } finally {
      setEnviando(false);
    }
  };

  const Erro = ({ texto }: { texto?: string }) =>
    texto ? <div style={{ fontSize: 12.5, color: "var(--clay)", marginTop: 6 }}>{texto}</div> : null;

  return (
    <div
      onClick={(e) => e.target === e.currentTarget && onFechar()}
      style={{
        position: "fixed", inset: 0, zIndex: 60, background: "rgba(26,22,25,.45)",
        display: "grid", placeItems: "center", padding: 18, overflowY: "auto",
      }}
    >
      <div
        ref={painel} role="dialog" aria-modal="true" aria-labelledby="titulo-novo-paciente"
        className="card" style={{ width: "100%", maxWidth: 520, padding: 24 }}
      >
        <div className="eyebrow" style={{ marginBottom: 8 }}>Acesso só por convite</div>
        <h2 id="titulo-novo-paciente" className="disp" style={{ fontSize: 24, fontWeight: 600, margin: "0 0 6px" }}>
          Convidar paciente
        </h2>
        <p style={{ fontSize: 13.5, color: "var(--ink-2)", margin: "0 0 20px", lineHeight: 1.5 }}>
          Ela entra pelo e-mail que você cadastrar. Alimentos e materiais começam vazios — você libera depois, na ficha.
        </p>

        <label className="eyebrow" htmlFor="np-nome" style={{ display: "block", marginBottom: 7 }}>Nome</label>
        <input
          id="np-nome" ref={primeiroCampo} className="input" value={nome} autoComplete="off"
          onChange={(e) => setNome(e.target.value)} placeholder="Nome completo"
          aria-invalid={!!erros.nome}
        />
        <Erro texto={erros.nome} />

        <label className="eyebrow" htmlFor="np-email" style={{ display: "block", margin: "16px 0 7px" }}>E-mail</label>
        <input
          id="np-email" className="input" type="email" value={email} autoComplete="off"
          onChange={(e) => setEmail(e.target.value)} placeholder="nome@email.com"
          aria-invalid={!!erros.email}
        />
        <Erro texto={erros.email} />

        <label className="eyebrow" htmlFor="np-objetivo" style={{ display: "block", margin: "16px 0 7px" }}>Objetivo</label>
        <input
          id="np-objetivo" className="input" value={objetivo} list="np-objetivos"
          onChange={(e) => setObjetivo(e.target.value)} aria-invalid={!!erros.objetivo}
        />
        <datalist id="np-objetivos">
          {OBJETIVOS.map((o) => <option key={o} value={o} />)}
        </datalist>
        <Erro texto={erros.objetivo} />

        <div className="eyebrow" style={{ margin: "18px 0 7px" }}>Mostrar quantidade em</div>
        <div style={{ display: "flex", gap: 7 }}>
          {([["g", "Gramas"], ["caseira", "Medida caseira"]] as const).map(([id, rotulo]) => (
            <button
              key={id} type="button" className={`chip ${preferenciaUnidade === id ? "on" : ""}`}
              aria-pressed={preferenciaUnidade === id} onClick={() => setPreferenciaUnidade(id)}
            >
              {rotulo}
            </button>
          ))}
        </div>

        <label style={{ display: "flex", gap: 10, alignItems: "flex-start", marginTop: 18, cursor: "pointer" }}>
          <input
            type="checkbox" checked={pesoModoCego} onChange={(e) => setPesoModoCego(e.target.checked)}
            style={{ marginTop: 3, width: 16, height: 16, accentColor: "var(--plum)", flexShrink: 0 }}
          />
          <span style={{ fontSize: 13.5, lineHeight: 1.5 }}>
            <strong style={{ fontWeight: 600 }}>Peso no modo discreto</strong>
            <span style={{ color: "var(--ink-2)" }}> — ela registra o peso, mas não vê o número. Só você acompanha.</span>
          </span>
        </label>

        {erroEnvio && (
          <div role="alert" style={{ marginTop: 18, padding: 12, borderRadius: 11, background: "var(--paper)", borderLeft: "3px solid var(--clay)", fontSize: 13.5, color: "var(--clay)", lineHeight: 1.5 }}>
            {erroEnvio}
          </div>
        )}

        <div className="row" style={{ marginTop: 22, flexWrap: "wrap" }}>
          <button className="btn" onClick={enviar} disabled={enviando}>
            {enviando ? "Enviando…" : "Enviar convite"}
          </button>
          <button className="btn ghost" onClick={onFechar} disabled={enviando}>Cancelar</button>
        </div>
      </div>
    </div>
  );
}
