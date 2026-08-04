import { useMemo, useState } from "react";
import { pacienteService } from "@/services";
import { chaves, useVersaoDe } from "@/store/revalidacaoStore";
import { useAsync } from "./useAsync";

/**
 * A lista e o contador "N ATIVOS" do topo do painel montam hooks separados
 * sobre a mesma consulta. A chave de revalidação é o que faz convidar (ou
 * encerrar o acesso de) uma paciente chegar nos dois — sem ela o cabeçalho
 * continuava dizendo "3 ATIVOS" com quatro na tela.
 */
export function usePacientes() {
  const versao = useVersaoDe(chaves.pacientes());
  const [estado, recarregar] = useAsync(() => pacienteService.listarPacientesComResumo(), [versao]);
  const [busca, setBusca] = useState("");
  const [incluirInativos, setIncluirInativos] = useState(false);

  const filtrados = useMemo(() => {
    if (estado.status !== "pronto") return [];
    return pacienteService.filtrarPacientes(estado.dado, busca, incluirInativos);
  }, [estado, busca, incluirInativos]);

  return { estado, filtrados, busca, setBusca, incluirInativos, setIncluirInativos, recarregar };
}

/** Só a contagem de ativas — para o cabeçalho, que não precisa da lista inteira em estado. */
export function useContagemAtivos(): number | null {
  const versao = useVersaoDe(chaves.pacientes());
  const [estado] = useAsync(() => pacienteService.listarPacientesComResumo(), [versao]);
  return estado.status === "pronto" ? estado.dado.filter((x) => x.paciente.ativo).length : null;
}
