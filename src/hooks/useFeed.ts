import { useCallback } from "react";
import { feedService } from "@/services";
import { useAsync } from "./useAsync";

export function useFeed() {
  const [estado, recarregar] = useAsync(() => feedService.listarFeed(), []);

  const curtir = useCallback(
    async (postId: string, pacienteId: string) => {
      await feedService.alternarCurtida(postId, pacienteId);
      recarregar();
    },
    [recarregar],
  );

  return { estado, curtir, recarregar };
}
