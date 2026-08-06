import { mfaRepository } from "@/repositories";
import { reiniciarDemonstracao as reiniciarBanco } from "@/repositories/mockDb";
import * as authService from "./authService";

/**
 * Devolve a demonstração ao estado de fábrica.
 *
 * Desde que o mock passou a persistir no localStorage, tudo o que se faz
 * testando fica salvo — plano publicado, paciente convidada, foto do prato,
 * check-in. Isso é o que se quer ao avaliar o produto, e é exatamente o que
 * atrapalha quando se quer recomeçar do começo.
 *
 * Limpa três armazenamentos separados: o "banco", a sessão e os dispositivos
 * confiáveis. Os dois últimos importam para o fluxo voltar inteiro — sem
 * eles, quem reinicia continua logado (talvez como uma paciente que deixou
 * de existir) e pula o MFA.
 *
 * Não recarrega a página: quem chama decide. As telas guardam dados já
 * buscados em estado do React, que este reset não alcança, então a chamada
 * precisa ser seguida de um reload.
 */
export async function reiniciarDemonstracao(): Promise<void> {
  reiniciarBanco();
  await authService.logout();
  await mfaRepository.esquecerDispositivos();
}
