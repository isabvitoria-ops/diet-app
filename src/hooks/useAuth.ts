import { useCallback, useEffect } from "react";
import { useAuthStore } from "@/store/authStore";
import { authService } from "@/services";

export function useAuth() {
  const { sessao, carregando, erro, definirSessao, definirCarregando, definirErro } = useAuthStore();

  useEffect(() => {
    let ativo = true;
    authService.sessaoAtual().then((s) => {
      if (ativo) {
        definirSessao(s);
        definirCarregando(false);
      }
    });
    return () => {
      ativo = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const entrar = useCallback(
    async (email: string, senha: string) => {
      definirErro(null);
      try {
        const s = await authService.login(email, senha);
        definirSessao(s);
        return s;
      } catch (e) {
        const msg = e instanceof Error ? e.message : "Não foi possível entrar.";
        definirErro(msg);
        throw e;
      }
    },
    [definirErro, definirSessao],
  );

  const sair = useCallback(async () => {
    await authService.logout();
    definirSessao(null);
  }, [definirSessao]);

  return { sessao, carregando, erro, entrar, sair };
}
