import type {
  Alimento,
  CategoriaComerFora,
  Configuracoes,
  Equivalencia,
  EventoHistorico,
  Favorito,
  Guia,
  NovoPaciente,
  Paciente,
  Plano,
} from "@/central/types";
import { exigirSupabase } from "@/central/supabase/cliente";
import {
  paraAlimento,
  paraCategoriaComerFora,
  paraConfiguracoes,
  paraEquivalencia,
  paraEvento,
  paraGrupo,
  paraGuia,
  paraPaciente,
  paraPlano,
  paraUnidade,
} from "./mapeadores";
import type { AlteracaoPaciente, DadosCatalogo, Repositorio } from "./repositorio";

/**
 * A implementação de produção.
 *
 * Repare no que NÃO está aqui: nenhuma verificação de "esta pessoa pode ver
 * isto?". Não é esquecimento — é o desenho. Quem filtra é a política de
 * acesso do banco (0003_rls.sql). Uma consulta feita por paciente vencido
 * volta vazia porque o Postgres não entrega a linha, não porque o código
 * abaixo tenha lembrado de perguntar. É isso que faz o §34 do briefing valer
 * mesmo se alguém chamar a API por fora do app.
 */

function erro(contexto: string, e: { message: string } | null): void {
  if (e) throw new Error(`${contexto}: ${e.message}`);
}

export const repositorioSupabase: Repositorio = {
  async carregarCatalogo(): Promise<DadosCatalogo> {
    const sb = exigirSupabase();

    const [unidades, grupos, alimentos, equivalencias, conteudos, configuracoes] = await Promise.all([
      sb.from("unidades").select("*").eq("ativo", true).order("ordem"),
      sb.from("grupos_alimentares").select("*").eq("ativo", true).order("ordem"),
      sb.from("alimentos").select("*").order("nome"),
      sb.from("equivalencias").select("*"),
      sb.from("conteudos").select("*").order("ordem"),
      sb.from("configuracoes").select("*"),
    ]);

    erro("unidades", unidades.error);
    erro("grupos", grupos.error);
    erro("alimentos", alimentos.error);
    erro("equivalências", equivalencias.error);
    erro("conteúdos", conteudos.error);
    erro("configurações", configuracoes.error);

    const linhasConteudo = conteudos.data ?? [];

    return {
      unidades: (unidades.data ?? []).map(paraUnidade),
      grupos: (grupos.data ?? []).map(paraGrupo),
      alimentos: (alimentos.data ?? []).map(paraAlimento),
      equivalencias: (equivalencias.data ?? []).map(paraEquivalencia),
      categoriasComerFora: linhasConteudo
        .filter((l) => l.tipo === "comer_fora")
        .map(paraCategoriaComerFora),
      guias: linhasConteudo.filter((l) => l.tipo === "guia").map(paraGuia),
      configuracoes: paraConfiguracoes(configuracoes.data ?? []),
    };
  },

  async listarFavoritos(): Promise<Favorito[]> {
    const sb = exigirSupabase();
    const { data, error } = await sb
      .from("favoritos")
      .select("*")
      .order("criado_em", { ascending: false });
    erro("favoritos", error);
    return (data ?? []).map((l) => ({
      id: `${l.tipo}:${l.ref_id}`,
      tipo: l.tipo,
      refId: l.ref_id,
      titulo: l.titulo,
      subtitulo: l.subtitulo,
      rota: l.rota,
      salvoEm: l.criado_em,
    }));
  },

  async salvarFavorito(favorito) {
    const sb = exigirSupabase();
    const { data: sessao } = await sb.auth.getUser();
    if (!sessao.user) throw new Error("Sessão expirada.");
    const { error } = await sb.from("favoritos").insert({
      perfil_id: sessao.user.id,
      tipo: favorito.tipo,
      ref_id: favorito.refId,
      titulo: favorito.titulo,
      subtitulo: favorito.subtitulo,
      rota: favorito.rota,
    });
    erro("salvar favorito", error);
  },

  async removerFavorito(id) {
    const sb = exigirSupabase();
    const [tipo, ...resto] = id.split(":");
    const { error } = await sb
      .from("favoritos")
      .delete()
      .eq("tipo", tipo)
      .eq("ref_id", resto.join(":"));
    erro("remover favorito", error);
  },

  async listarPlanos(): Promise<Plano[]> {
    const sb = exigirSupabase();
    const { data, error } = await sb.from("planos").select("*").eq("ativo", true).order("ordem");
    erro("planos", error);
    return (data ?? []).map(paraPlano);
  },

  async listarPacientes(): Promise<Paciente[]> {
    const sb = exigirSupabase();
    const { data, error } = await sb.from("pacientes_visao").select("*").order("nome");
    erro("pacientes", error);
    return (data ?? []).map(paraPaciente);
  },

  async criarPaciente(dados: NovoPaciente): Promise<Paciente> {
    const sb = exigirSupabase();
    const { data, error } = await sb
      .from("pacientes")
      .insert({
        nome: dados.nome,
        email: dados.email.toLowerCase().trim(),
        telefone: dados.telefone ?? null,
        plano_id: dados.planoId,
        data_inicio: dados.dataInicio,
        data_fim: dados.dataFim,
        observacoes: dados.observacoes ?? null,
      })
      .select()
      .single();
    erro("cadastrar paciente", error);
    return paraPaciente(data ?? {});
  },

  async alterarPaciente(id, alteracao: AlteracaoPaciente) {
    const sb = exigirSupabase();
    const linha: Record<string, unknown> = {};
    if (alteracao.nome !== undefined) linha.nome = alteracao.nome;
    if (alteracao.email !== undefined) linha.email = alteracao.email.toLowerCase().trim();
    if (alteracao.telefone !== undefined) linha.telefone = alteracao.telefone;
    if (alteracao.planoId !== undefined) linha.plano_id = alteracao.planoId;
    if (alteracao.dataInicio !== undefined) linha.data_inicio = alteracao.dataInicio;
    if (alteracao.dataFim !== undefined) linha.data_fim = alteracao.dataFim;
    if (alteracao.status !== undefined) linha.status = alteracao.status;
    if (alteracao.observacoes !== undefined) linha.observacoes = alteracao.observacoes;
    const { error } = await sb.from("pacientes").update(linha).eq("id", id);
    erro("alterar paciente", error);
  },

  async excluirPaciente(id) {
    const sb = exigirSupabase();
    const { error } = await sb.from("pacientes").delete().eq("id", id);
    erro("excluir paciente", error);
  },

  /**
   * Envia o convite e anota o envio.
   *
   * O e-mail sai pelo próprio Supabase Auth, por link mágico. Foi escolhido
   * assim porque `inviteUserByEmail` exige a chave de serviço, que não pode
   * existir no navegador de jeito nenhum (§64) — precisaria de um servidor
   * só para isso. O link mágico faz o mesmo trabalho com a chave pública.
   *
   * E continua valendo a regra central: receber o e-mail cria uma conta, não
   * cria acesso. O acesso vem da linha em `pacientes`, que só a nutricionista
   * escreve, e da validade do período.
   */
  async registrarConvite(pacienteId, email) {
    const sb = exigirSupabase();
    const { error: erroEnvio } = await sb.auth.signInWithOtp({
      email: email.toLowerCase().trim(),
      options: {
        shouldCreateUser: true,
        emailRedirectTo: `${window.location.origin}/definir-senha`,
      },
    });
    erro("enviar convite", erroEnvio);

    const { data: sessao } = await sb.auth.getUser();
    const { error } = await sb.from("convites").insert({
      paciente_id: pacienteId,
      email: email.toLowerCase().trim(),
      enviado_por: sessao.user?.id ?? null,
    });
    erro("registrar convite", error);
  },

  async historicoDoPaciente(pacienteId): Promise<EventoHistorico[]> {
    const sb = exigirSupabase();
    const { data, error } = await sb
      .from("historico_admin")
      .select("*")
      .eq("paciente_id", pacienteId)
      .order("criado_em", { ascending: false })
      .limit(50);
    erro("histórico", error);
    return (data ?? []).map(paraEvento);
  },

  async salvarAlimento(alimento: Alimento, ativo: boolean) {
    const sb = exigirSupabase();
    const { error } = await sb.from("alimentos").upsert({
      id: alimento.id,
      nome: alimento.nome,
      grupo_id: alimento.grupoId,
      unidade_base_id: alimento.unidadeBaseId,
      porcao_quantidade: alimento.porcao?.quantidade ?? null,
      porcao_unidade_id: alimento.porcao?.unidadeId ?? null,
      medidas: alimento.medidas,
      sem_gluten: alimento.atributos.semGluten,
      sem_lactose: alimento.atributos.semLactose,
      tags: alimento.tags,
      imagem_url: alimento.imagem,
      observacao: alimento.observacao,
      ativo,
    });
    erro("salvar alimento", error);
  },

  async salvarEquivalencia(equivalencia: Equivalencia, ativo: boolean) {
    const sb = exigirSupabase();
    const { error } = await sb.from("equivalencias").upsert({
      id: equivalencia.id,
      origem_alimento_id: equivalencia.origemAlimentoId,
      destino_alimento_id: equivalencia.destinoAlimentoId,
      tipo: equivalencia.regra.tipo,
      regra: equivalencia.regra,
      bidirecional: equivalencia.bidirecional,
      fonte: equivalencia.fonte,
      observacao: equivalencia.observacao,
      ativo,
    });
    erro("salvar equivalência", error);
  },

  async salvarCategoriaComerFora(categoria: CategoriaComerFora) {
    const sb = exigirSupabase();
    const { error } = await sb.from("conteudos").upsert({
      id: categoria.id,
      tipo: "comer_fora",
      titulo: categoria.nome,
      resumo: categoria.resumo,
      icone: categoria.icone,
      ordem: categoria.ordem,
      status: categoria.status === "publicado" ? "publicado" : "rascunho",
      corpo: {
        introducao: categoria.introducao,
        decisoes: categoria.decisoes,
        lembretes: categoria.lembretes,
      },
      tags: categoria.tags,
    });
    erro("salvar categoria", error);
  },

  async salvarGuia(guia: Guia) {
    const sb = exigirSupabase();
    const { error } = await sb.from("conteudos").upsert({
      id: guia.id,
      tipo: "guia",
      titulo: guia.titulo,
      tema: guia.tema,
      resumo: guia.resumo,
      ordem: guia.ordem,
      status: guia.status === "publicado" ? "publicado" : "rascunho",
      corpo: { secoes: guia.secoes },
      tags: guia.tags,
    });
    erro("salvar guia", error);
  },

  async salvarConfiguracoes(configuracoes: Configuracoes) {
    const sb = exigirSupabase();
    const linhas = [
      { chave: "nome_central", valor: configuracoes.nomeCentral },
      { chave: "frase_home", valor: configuracoes.fraseHome },
      { chave: "lema", valor: configuracoes.lema },
      { chave: "whatsapp", valor: configuracoes.whatsapp },
      { chave: "nome_nutricionista", valor: configuracoes.nomeNutricionista },
      { chave: "alerta_vencimento_dias", valor: configuracoes.alertaVencimentoDias },
    ];
    const { error } = await sb.from("configuracoes").upsert(linhas);
    erro("salvar configurações", error);
  },

  async registrarAcesso() {
    const sb = exigirSupabase();
    // Marcar presença não pode atrapalhar o uso do app: se falhar, segue.
    try {
      await sb.rpc("registrar_acesso");
    } catch {
      /* rede instável ou sessão trocando — o app continua igual */
    }
  },
};
