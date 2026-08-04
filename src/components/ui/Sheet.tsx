import { useEffect, useRef, type ReactNode } from "react";

interface SheetProps {
  onFechar: () => void;
  titulo?: string;
  cheia?: boolean;
  children: ReactNode;
}

/**
 * Modal deslizante de baixo (veil + sheet) — porte do padrão usado nos dois
 * protótipos, com o que faltava de acessibilidade (briefing §19): foco vai
 * para o modal ao abrir, Esc fecha, `role="dialog"`/`aria-modal` para
 * leitor de tela. Clique no fundo escuro fecha, igual ao original.
 */
export function Sheet({ onFechar, titulo, cheia = false, children }: SheetProps) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    ref.current?.focus();
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") onFechar();
    };
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [onFechar]);

  return (
    <div className="veil" onClick={(e) => e.target === e.currentTarget && onFechar()}>
      <div
        ref={ref}
        className={`sheet ${cheia ? "full" : ""}`}
        role="dialog"
        aria-modal="true"
        aria-label={titulo}
        tabIndex={-1}
      >
        <div className="grab" aria-hidden="true" />
        {children}
      </div>
    </div>
  );
}
