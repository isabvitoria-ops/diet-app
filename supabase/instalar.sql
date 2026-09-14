-- =============================================================================
-- CENTRAL DO PACIENTE — instalação completa do banco
--
-- ARQUIVO GERADO por `npm run instalador`. Não edite aqui: edite os arquivos
-- de supabase/migracoes/ e gere de novo.
--
-- COMO USAR
--   1. Abra o seu projeto no Supabase.
--   2. Menu da esquerda → SQL Editor → New query.
--   3. Cole TODO o conteúdo deste arquivo.
--   4. Clique em Run.
--
-- Pode rodar mais de uma vez sem medo: tudo é "crie se não existir" e os
-- dados iniciais são inseridos com "on conflict do nothing", então nada que
-- você já tiver cadastrado é apagado ou duplicado.
--
-- Contém: 0001_esquema.sql, 0002_funcoes.sql, 0003_rls.sql, 0004_dados_iniciais.sql, 0005_permissoes.sql
-- =============================================================================


-- ###########################################################################
-- 0001_esquema.sql
-- ###########################################################################

-- =============================================================================
-- CENTRAL DO PACIENTE — 0001: esquema
--
-- Tabelas, índices e o vocabulário do domínio. Nada de política de acesso
-- aqui: isso está em 0003_rls.sql, depois das funções que as políticas usam.
--
-- Convenção de datas: `data_inicio` e `data_fim` são DATE, não timestamp. O
-- acesso de um paciente vale o dia inteiro da data de fim, no fuso de São
-- Paulo — quem termina em 30/06 continua entrando às 23h de 30/06.
-- =============================================================================

create extension if not exists citext;

-- -----------------------------------------------------------------------------
-- Pessoas
-- -----------------------------------------------------------------------------

-- Um perfil por conta autenticada. É criado automaticamente pelo gatilho
-- `ao_criar_usuario` (ver 0002) — o app nunca insere aqui.
create table if not exists perfis (
  id uuid primary key references auth.users (id) on delete cascade,
  nome text,
  email citext not null,
  papel text not null default 'paciente' check (papel in ('admin', 'paciente')),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create index if not exists perfis_email_idx on perfis (email);
create index if not exists perfis_papel_idx on perfis (papel);

-- -----------------------------------------------------------------------------
-- Planos e pacientes
-- -----------------------------------------------------------------------------

create table if not exists planos (
  id text primary key,
  nome text not null,
  duracao_dias integer not null check (duracao_dias > 0),
  descricao text,
  ordem integer not null default 0,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

-- O paciente é cadastrado pela nutricionista ANTES de existir conta de
-- acesso: por isso `perfil_id` nasce nulo e o e-mail é a chave de encontro.
-- É essa separação que faz valer a regra "convite não é acesso" — a conta
-- pode existir sem que exista linha aqui, e aí o acesso é zero.
--
-- `status` guarda só o que é decisão humana: convite pendente, ativo,
-- suspenso. "Expirado", "próximo do vencimento" e "não iniciado" NÃO são
-- gravados: saem das datas, toda vez que são perguntados (ver `situacao` em
-- 0002). Sem isso seria preciso uma rotina diária virando status — e um dia
-- que a rotina falhasse, paciente vencido continuaria entrando.
create table if not exists pacientes (
  id uuid primary key default gen_random_uuid(),
  perfil_id uuid unique references perfis (id) on delete set null,
  email citext not null unique,
  nome text not null,
  telefone text,
  plano_id text references planos (id),
  data_inicio date not null,
  data_fim date not null,
  status text not null default 'convite_pendente'
    check (status in ('convite_pendente', 'ativo', 'suspenso')),
  observacoes text,
  ultimo_acesso timestamptz,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint periodo_coerente check (data_fim >= data_inicio)
);

create index if not exists pacientes_status_idx on pacientes (status);
create index if not exists pacientes_data_fim_idx on pacientes (data_fim);
create index if not exists pacientes_perfil_idx on pacientes (perfil_id);

-- Registro de cada envio de convite. A linha de `pacientes` já diz que há um
-- convite pendente; esta tabela responde "quando mandei da última vez?", que
-- é o que a tela administrativa precisa mostrar.
create table if not exists convites (
  id uuid primary key default gen_random_uuid(),
  paciente_id uuid not null references pacientes (id) on delete cascade,
  email citext not null,
  enviado_em timestamptz not null default now(),
  enviado_por uuid references perfis (id) on delete set null,
  aceito_em timestamptz
);

create index if not exists convites_paciente_idx on convites (paciente_id, enviado_em desc);

-- Trilha administrativa: quem fez o quê com qual paciente.
create table if not exists historico_admin (
  id uuid primary key default gen_random_uuid(),
  paciente_id uuid references pacientes (id) on delete cascade,
  ator_perfil_id uuid references perfis (id) on delete set null,
  evento text not null,
  detalhe jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now()
);

create index if not exists historico_paciente_idx on historico_admin (paciente_id, criado_em desc);

-- -----------------------------------------------------------------------------
-- Catálogo de alimentos
-- -----------------------------------------------------------------------------

create table if not exists unidades (
  id text primary key,
  rotulo text not null,
  abreviacao text not null,
  singular text not null,
  continua boolean not null default true,
  ordem integer not null default 0,
  ativo boolean not null default true
);

create table if not exists grupos_alimentares (
  id text primary key,
  nome text not null,
  descricao text,
  ordem integer not null default 0,
  -- Regra do grupo. Hoje: {"tipo":"porcoes"} ou
  -- {"tipo":"livre","texto":"...","minimos":[{"refeicao":"Almoço","medida":{...}}]}
  regra jsonb,
  troca_por_porcao boolean not null default true,
  -- Grupos para os quais uma porção deste grupo pode ser convertida, além do
  -- próprio. É de MÃO ÚNICA: carboidratos leva {"frutas"}, e frutas leva {},
  -- porque no material carboidrato vira fruta e fruta não vira carboidrato.
  troca_para_grupos text[] not null default '{}',
  tags text[] not null default '{}',
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create table if not exists alimentos (
  id text primary key,
  nome text not null,
  grupo_id text not null references grupos_alimentares (id),
  unidade_base_id text not null references unidades (id),
  -- Porção de referência. Nula enquanto a nutricionista não cadastrar: o
  -- alimento aparece na lista marcado como pendente e fica fora da
  -- calculadora, em vez de ganhar um valor plausível inventado.
  porcao_quantidade numeric,
  porcao_unidade_id text references unidades (id),
  -- Livre por decisão da nutricionista (o limão), que é diferente de porção
  -- nula por dado faltando. As telas contam os dois de formas opostas.
  quantidade_livre boolean not null default false,
  -- [{"unidadeId":"colher-sopa","equivalenteNaBase":25,"rotulo":null}]
  medidas jsonb not null default '[]'::jsonb,
  -- Três estados de propósito: true, false e NULL ("ainda não informei").
  sem_gluten boolean,
  sem_lactose boolean,
  tags text[] not null default '{}',
  imagem_url text,
  observacao text,
  nivel_acesso text not null default 'paciente'
    check (nivel_acesso in ('publico', 'paciente', 'premium')),
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint porcao_completa check (
    (porcao_quantidade is null and porcao_unidade_id is null)
    or (porcao_quantidade is not null and porcao_unidade_id is not null)
  )
);

create index if not exists alimentos_grupo_idx on alimentos (grupo_id);
create index if not exists alimentos_tags_idx on alimentos using gin (tags);

-- Equivalência entre dois alimentos. `tipo` + `regra` porque nem toda troca
-- é proporcional: "tabela" guarda pontos medidos e o sistema interpola entre
-- eles sem nunca extrapolar; "fixa" ignora a quantidade informada.
create table if not exists equivalencias (
  id text primary key,
  origem_alimento_id text not null references alimentos (id) on delete cascade,
  destino_alimento_id text not null references alimentos (id) on delete cascade,
  tipo text not null default 'proporcional' check (tipo in ('proporcional', 'tabela', 'fixa')),
  regra jsonb not null,
  bidirecional boolean not null default true,
  fonte text,
  observacao text,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint alimentos_diferentes check (origem_alimento_id <> destino_alimento_id),
  unique (origem_alimento_id, destino_alimento_id)
);

create index if not exists equivalencias_origem_idx on equivalencias (origem_alimento_id);
create index if not exists equivalencias_destino_idx on equivalencias (destino_alimento_id);

-- -----------------------------------------------------------------------------
-- Conteúdo editorial (guias e comer fora)
-- -----------------------------------------------------------------------------

-- Uma tabela para os dois, porque a diferença está na forma do `corpo` e não
-- no ciclo de vida: os dois são escritos, publicados, marcados com nível de
-- acesso e buscados do mesmo jeito. Separar em duas tabelas (e mais duas de
-- categoria e tag, para uma dúzia de linhas) seria estrutura a mais sem
-- ganho nenhum.
--
-- corpo de um guia:       {"secoes":[{"id","titulo","paragrafos":[],"itens":[]}]}
-- corpo de comer fora:    {"introducao","lembretes":[],"decisoes":[{"id","titulo","pergunta","opcoes":[...]}]}
create table if not exists conteudos (
  id text primary key,
  tipo text not null check (tipo in ('guia', 'comer_fora')),
  titulo text not null,
  -- Agrupa na listagem: o tema do guia ("Digestão") ou nada, em comer fora.
  tema text,
  resumo text,
  icone text,
  ordem integer not null default 0,
  status text not null default 'rascunho' check (status in ('rascunho', 'publicado')),
  nivel_acesso text not null default 'paciente'
    check (nivel_acesso in ('publico', 'paciente', 'premium')),
  corpo jsonb not null default '{}'::jsonb,
  tags text[] not null default '{}',
  imagem_url text,
  -- §18 do briefing: a kcal fica guardada mesmo quando não é exibida.
  mostrar_kcal boolean not null default false,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create index if not exists conteudos_tipo_idx on conteudos (tipo, ordem);
create index if not exists conteudos_tags_idx on conteudos using gin (tags);

-- -----------------------------------------------------------------------------
-- Dados do paciente e configuração do app
-- -----------------------------------------------------------------------------

create table if not exists favoritos (
  id uuid primary key default gen_random_uuid(),
  perfil_id uuid not null references perfis (id) on delete cascade,
  tipo text not null,
  ref_id text not null,
  titulo text not null,
  subtitulo text,
  rota text not null,
  criado_em timestamptz not null default now(),
  unique (perfil_id, tipo, ref_id)
);

create index if not exists favoritos_perfil_idx on favoritos (perfil_id, criado_em desc);

-- Chave/valor para o que hoje seria constante no código: WhatsApp, nome da
-- Central, textos. Trocar o número da nutricionista tem que ser uma edição,
-- não uma caça pelo código inteiro.
create table if not exists configuracoes (
  chave text primary key,
  valor jsonb not null,
  descricao text,
  atualizado_em timestamptz not null default now()
);


-- ###########################################################################
-- 0002_funcoes.sql
-- ###########################################################################

-- =============================================================================
-- CENTRAL DO PACIENTE — 0002: funções, gatilhos e visões
--
-- Aqui mora a regra que o briefing chama de fundamental:
--
--   CONVITE ≠ ACESSO
--   acesso = conta autenticada + paciente vinculado + não suspenso
--            + hoje dentro do período
--
-- `tem_acesso()` é a única implementação dessa frase no sistema inteiro. As
-- políticas de 0003 chamam ela; o frontend chama `meu_acesso()`, que chama
-- ela. Não há uma segunda cópia da regra para sair de sincronia.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Auxiliares
-- -----------------------------------------------------------------------------

-- O dia de hoje no fuso de quem usa o app, não no fuso do servidor. Sem isso,
-- entre 21h e meia-noite o Brasil já estaria no "amanhã" do UTC e o acesso de
-- quem vence hoje cairia três horas antes da hora.
create or replace function hoje_sp()
returns date
language sql
stable
as $$
  select (now() at time zone 'America/Sao_Paulo')::date;
$$;

create or replace function config_inteiro(p_chave text, p_padrao integer)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select (valor #>> '{}')::integer from configuracoes where chave = p_chave), p_padrao);
$$;

-- `security definer` de propósito: a função precisa ler `perfis` sem passar
-- pela política de `perfis`, senão a política que chama esta função entraria
-- em recursão infinita.
create or replace function e_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from perfis where id = auth.uid() and papel = 'admin');
$$;

-- -----------------------------------------------------------------------------
-- Situação do paciente — derivada, nunca gravada
-- -----------------------------------------------------------------------------

-- "Expirado" não é um status que alguém escreve: é uma consequência da data.
-- Calcular na hora da pergunta significa que o acesso termina sozinho à
-- meia-noite, sem rotina diária, sem ninguém lembrar de rodar nada — e sem o
-- risco de um dia a rotina falhar e um plano vencido continuar aberto.
create or replace function situacao_paciente(
  p_status text,
  p_perfil_id uuid,
  p_data_inicio date,
  p_data_fim date
)
returns text
language sql
stable
as $$
  select case
    when p_perfil_id is null then 'convite_pendente'
    when p_status = 'suspenso' then 'suspenso'
    when hoje_sp() < p_data_inicio then 'nao_iniciado'
    when hoje_sp() > p_data_fim then 'expirado'
    when p_data_fim - hoje_sp() <= config_inteiro('alerta_vencimento_dias', 15)
      then 'proximo_do_vencimento'
    else 'ativo'
  end;
$$;

-- A frase do briefing, em SQL. Repare que ela não pergunta nada ao frontend:
-- mesmo que alguém chame a API direto, com um token válido de paciente
-- vencido, esta função devolve falso e as políticas não entregam linha
-- nenhuma.
create or replace function tem_acesso()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from pacientes p
    where p.perfil_id = auth.uid()
      and p.status = 'ativo'
      and hoje_sp() between p.data_inicio and p.data_fim
  );
$$;

-- `security_invoker = true` é obrigatório: sem isso a visão roda com os
-- poderes de quem a criou e entregaria a lista inteira de pacientes para
-- qualquer um que a consultasse, contornando a política da tabela.
create or replace view pacientes_visao
with (security_invoker = true)
as
select
  p.*,
  situacao_paciente(p.status, p.perfil_id, p.data_inicio, p.data_fim) as situacao,
  (p.data_fim - hoje_sp()) as dias_restantes,
  pl.nome as plano_nome,
  pl.duracao_dias as plano_duracao_dias,
  (select max(c.enviado_em) from convites c where c.paciente_id = p.id) as convite_enviado_em
from pacientes p
left join planos pl on pl.id = p.plano_id;

-- -----------------------------------------------------------------------------
-- Ciclo de vida da conta
-- -----------------------------------------------------------------------------

-- Criar conta cria PERFIL, não acesso. O vínculo com um paciente só acontece
-- se a nutricionista já tiver cadastrado aquele e-mail. Quem se cadastra sem
-- convite fica com uma conta autenticada e zero conteúdo — que é exatamente
-- o comportamento pedido.
create or replace function ao_criar_usuario()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into perfis (id, email, nome, papel)
  values (
    new.id,
    new.email,
    coalesce(nullif(new.raw_user_meta_data ->> 'nome', ''), split_part(new.email, '@', 1)),
    'paciente'
  )
  on conflict (id) do nothing;

  update pacientes
     set perfil_id = new.id,
         status = case when status = 'convite_pendente' then 'ativo' else status end,
         atualizado_em = now()
   where email = new.email
     and perfil_id is null;

  update convites
     set aceito_em = now()
   where email = new.email
     and aceito_em is null;

  return new;
end;
$$;

drop trigger if exists ao_criar_usuario on auth.users;
create trigger ao_criar_usuario
after insert on auth.users
for each row execute function ao_criar_usuario();

-- O caminho inverso: a nutricionista cadastra alguém que já tinha conta.
--
-- E o caso que faltava: quando ela CORRIGE o e-mail de um paciente já
-- vinculado, a conta antiga precisa ser solta. Sem isso, o acesso continuaria
-- valendo para o endereço errado — que é justamente de quem ela quis tirar —
-- e o cadastro passaria a dizer uma coisa enquanto o banco fazia outra.
create or replace function vincular_paciente_ao_perfil()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_perfil uuid;
  v_email_da_conta citext;
begin
  if tg_op = 'UPDATE' and new.perfil_id is not null and new.email is distinct from old.email then
    select email into v_email_da_conta from perfis where id = new.perfil_id;
    if v_email_da_conta is distinct from new.email then
      new.perfil_id := null;
      new.status := 'convite_pendente';
    end if;
  end if;

  if new.perfil_id is null then
    select id into v_perfil from perfis where email = new.email limit 1;
    if v_perfil is not null then
      new.perfil_id := v_perfil;
      if new.status = 'convite_pendente' then
        new.status := 'ativo';
      end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists vincular_paciente on pacientes;
create trigger vincular_paciente
before insert or update of email, perfil_id on pacientes
for each row execute function vincular_paciente_ao_perfil();

-- -----------------------------------------------------------------------------
-- Trilha administrativa
-- -----------------------------------------------------------------------------

-- Gravar o histórico por gatilho, e não pela tela, garante que toda mudança
-- fique registrada — inclusive a feita direto no painel do Supabase.
create or replace function registrar_evento_paciente()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_evento text;
  v_detalhe jsonb := '{}'::jsonb;
begin
  if tg_op = 'INSERT' then
    v_evento := 'paciente_cadastrado';
    v_detalhe := jsonb_build_object('plano', new.plano_id, 'inicio', new.data_inicio, 'fim', new.data_fim);
  else
    if new.status is distinct from old.status then
      v_evento := case new.status
        when 'suspenso' then 'suspenso'
        when 'ativo' then case when old.status = 'suspenso' then 'reativado' else 'conta_ativada' end
        else 'status_alterado'
      end;
      v_detalhe := jsonb_build_object('de', old.status, 'para', new.status);
    elsif new.data_fim is distinct from old.data_fim or new.plano_id is distinct from old.plano_id then
      v_evento := 'renovado';
      v_detalhe := jsonb_build_object(
        'plano_anterior', old.plano_id, 'plano', new.plano_id,
        'fim_anterior', old.data_fim, 'fim', new.data_fim,
        'inicio_anterior', old.data_inicio, 'inicio', new.data_inicio
      );
    elsif new.perfil_id is distinct from old.perfil_id and new.perfil_id is not null then
      v_evento := 'conta_vinculada';
    else
      return new;
    end if;
  end if;

  insert into historico_admin (paciente_id, ator_perfil_id, evento, detalhe)
  values (new.id, auth.uid(), v_evento, v_detalhe);

  return new;
end;
$$;

drop trigger if exists registrar_evento on pacientes;
create trigger registrar_evento
after insert or update on pacientes
for each row execute function registrar_evento_paciente();

create or replace function tocar_atualizado_em()
returns trigger
language plpgsql
as $$
begin
  new.atualizado_em := now();
  return new;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array[
    'perfis', 'planos', 'pacientes', 'grupos_alimentares',
    'alimentos', 'equivalencias', 'conteudos'
  ] loop
    execute format('drop trigger if exists tocar_atualizado on %I', t);
    execute format(
      'create trigger tocar_atualizado before update on %I for each row execute function tocar_atualizado_em()',
      t
    );
  end loop;
end;
$$;

-- -----------------------------------------------------------------------------
-- O que o app chama
-- -----------------------------------------------------------------------------

-- Uma chamada só, no carregamento: quem sou, o que posso ver, até quando.
-- Devolve sempre um objeto — nunca erro — para que a tela de "acesso
-- encerrado" seja um caminho normal do app e não um estado de falha.
create or replace function meu_acesso()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'autenticado', auth.uid() is not null,
    'perfilId', auth.uid(),
    'papel', coalesce((select papel from perfis where id = auth.uid()), 'paciente'),
    'nome', (select coalesce(pa.nome, pe.nome) from perfis pe
             left join pacientes pa on pa.perfil_id = pe.id where pe.id = auth.uid()),
    'email', (select email::text from perfis where id = auth.uid()),
    'temAcesso', tem_acesso() or e_admin(),
    'situacao', coalesce(
      (select situacao_paciente(p.status, p.perfil_id, p.data_inicio, p.data_fim)
         from pacientes p where p.perfil_id = auth.uid()),
      case when e_admin() then 'admin' else 'sem_cadastro' end
    ),
    'dataInicio', (select data_inicio from pacientes where perfil_id = auth.uid()),
    'dataFim', (select data_fim from pacientes where perfil_id = auth.uid()),
    'diasRestantes', (select data_fim - hoje_sp() from pacientes where perfil_id = auth.uid()),
    'plano', (select pl.nome from pacientes p join planos pl on pl.id = p.plano_id
               where p.perfil_id = auth.uid())
  );
$$;

-- O paciente não tem permissão de escrita na própria linha (senão poderia
-- esticar a própria data de fim). Marcar presença passa por aqui, que só
-- toca uma coluna.
create or replace function registrar_acesso()
returns void
language sql
security definer
set search_path = public
as $$
  update pacientes set ultimo_acesso = now() where perfil_id = auth.uid();
$$;


-- ###########################################################################
-- 0003_rls.sql
-- ###########################################################################

-- =============================================================================
-- CENTRAL DO PACIENTE — 0003: Row Level Security
--
-- O briefing é explícito (§34): esconder conteúdo no frontend não é
-- segurança. Um paciente vencido que abrir a URL antiga, ou que chamar a API
-- direto com o token dele, tem que receber vazio. É o que estas políticas
-- fazem — a decisão acontece no banco, antes de qualquer linha sair dele.
--
-- Duas funções decidem tudo:
--   e_admin()    — a conta é da nutricionista
--   tem_acesso() — paciente vinculado, não suspenso, dentro do período
-- =============================================================================

alter table perfis            enable row level security;
alter table planos            enable row level security;
alter table pacientes         enable row level security;
alter table convites          enable row level security;
alter table historico_admin   enable row level security;
alter table unidades          enable row level security;
alter table grupos_alimentares enable row level security;
alter table alimentos         enable row level security;
alter table equivalencias     enable row level security;
alter table conteudos         enable row level security;
alter table favoritos         enable row level security;
alter table configuracoes     enable row level security;

grant usage on schema public to anon, authenticated;
grant select on pacientes_visao to authenticated;

-- -----------------------------------------------------------------------------
-- Perfis
-- -----------------------------------------------------------------------------

drop policy if exists perfis_leitura on perfis;
create policy perfis_leitura on perfis
  for select using (id = auth.uid() or e_admin());

-- O paciente não escreve no próprio perfil: se pudesse, poderia trocar
-- `papel` para 'admin'. Nome e e-mail são mantidos pela nutricionista.
drop policy if exists perfis_admin_escreve on perfis;
create policy perfis_admin_escreve on perfis
  for all using (e_admin()) with check (e_admin());

-- -----------------------------------------------------------------------------
-- Planos
-- -----------------------------------------------------------------------------

drop policy if exists planos_leitura on planos;
create policy planos_leitura on planos
  for select to authenticated using (true);

drop policy if exists planos_admin on planos;
create policy planos_admin on planos
  for all using (e_admin()) with check (e_admin());

-- -----------------------------------------------------------------------------
-- Pacientes
-- -----------------------------------------------------------------------------

-- Cada paciente enxerga uma linha: a dele. Não existe política que devolva a
-- linha de outro paciente para quem não é admin.
drop policy if exists pacientes_leitura on pacientes;
create policy pacientes_leitura on pacientes
  for select using (perfil_id = auth.uid() or e_admin());

-- Escrita é só da nutricionista. É isto que impede o paciente de esticar a
-- própria `data_fim` ou de tirar a própria suspensão.
drop policy if exists pacientes_admin on pacientes;
create policy pacientes_admin on pacientes
  for all using (e_admin()) with check (e_admin());

-- -----------------------------------------------------------------------------
-- Convites e histórico — só administrativo
-- -----------------------------------------------------------------------------

drop policy if exists convites_admin on convites;
create policy convites_admin on convites
  for all using (e_admin()) with check (e_admin());

drop policy if exists historico_admin_politica on historico_admin;
create policy historico_admin_politica on historico_admin
  for all using (e_admin()) with check (e_admin());

-- -----------------------------------------------------------------------------
-- Vocabulário do catálogo
-- -----------------------------------------------------------------------------

-- Unidades e grupos são vocabulário ("Gramas", "Carboidratos"), não
-- conteúdo: qualquer conta autenticada lê, e isso não revela nada do
-- material da nutricionista.
drop policy if exists unidades_leitura on unidades;
create policy unidades_leitura on unidades for select to authenticated using (true);

drop policy if exists unidades_admin on unidades;
create policy unidades_admin on unidades for all using (e_admin()) with check (e_admin());

drop policy if exists grupos_leitura on grupos_alimentares;
create policy grupos_leitura on grupos_alimentares for select to authenticated using (true);

drop policy if exists grupos_admin on grupos_alimentares;
create policy grupos_admin on grupos_alimentares for all using (e_admin()) with check (e_admin());

-- -----------------------------------------------------------------------------
-- Conteúdo protegido
-- -----------------------------------------------------------------------------

-- A regra de acesso do briefing aplicada ao catálogo. Item inativo e item de
-- nível restrito só saem para quem tem acesso válido; a nutricionista vê
-- tudo, inclusive rascunho e desativado, porque é ela quem edita.
drop policy if exists alimentos_leitura on alimentos;
create policy alimentos_leitura on alimentos
  for select using (
    e_admin()
    or (ativo and (nivel_acesso = 'publico' or tem_acesso()))
  );

drop policy if exists alimentos_admin on alimentos;
create policy alimentos_admin on alimentos for all using (e_admin()) with check (e_admin());

drop policy if exists equivalencias_leitura on equivalencias;
create policy equivalencias_leitura on equivalencias
  for select using (e_admin() or (ativo and tem_acesso()));

drop policy if exists equivalencias_admin on equivalencias;
create policy equivalencias_admin on equivalencias for all using (e_admin()) with check (e_admin());

drop policy if exists conteudos_leitura on conteudos;
create policy conteudos_leitura on conteudos
  for select using (
    e_admin()
    or (
      ativo
      and status = 'publicado'
      and (nivel_acesso = 'publico' or tem_acesso())
    )
  );

drop policy if exists conteudos_admin on conteudos;
create policy conteudos_admin on conteudos for all using (e_admin()) with check (e_admin());

-- -----------------------------------------------------------------------------
-- Favoritos
-- -----------------------------------------------------------------------------

drop policy if exists favoritos_leitura on favoritos;
create policy favoritos_leitura on favoritos
  for select using (perfil_id = auth.uid());

-- Salvar exige acesso válido: não dá para guardar o que não se pode ver.
-- Ler o que já foi salvo continua permitido mesmo depois de vencer, porque
-- é dado do próprio paciente — mas a tela do conteúdo em si não abre.
drop policy if exists favoritos_insercao on favoritos;
create policy favoritos_insercao on favoritos
  for insert with check (perfil_id = auth.uid() and tem_acesso());

drop policy if exists favoritos_remocao on favoritos;
create policy favoritos_remocao on favoritos
  for delete using (perfil_id = auth.uid());

-- -----------------------------------------------------------------------------
-- Configurações
-- -----------------------------------------------------------------------------

-- O WhatsApp e o nome da Central precisam aparecer até na tela de "acesso
-- encerrado", que é justamente onde o paciente vai querer falar com a
-- nutricionista. Por isso a leitura é aberta a qualquer autenticado.
drop policy if exists configuracoes_leitura on configuracoes;
create policy configuracoes_leitura on configuracoes for select to authenticated using (true);

drop policy if exists configuracoes_admin on configuracoes;
create policy configuracoes_admin on configuracoes for all using (e_admin()) with check (e_admin());


-- ###########################################################################
-- 0004_dados_iniciais.sql
-- ###########################################################################

-- =============================================================================
-- CENTRAL DO PACIENTE — 0004: dados iniciais
--
-- ARQUIVO GERADO. Não edite à mão: ele sai de src/central/dados/sementes/
-- pelo comando `npm run seed`. Editar aqui faz o banco e o modo local do app
-- discordarem na primeira vez que alguém rodar o gerador de novo.
--
-- Tudo é `on conflict do nothing`: rodar duas vezes não duplica nem apaga o
-- que você já tiver cadastrado pelo painel.
-- =============================================================================

-- Planos ----------------------------------------------------------------------
insert into planos (id, nome, duracao_dias, descricao, ordem, ativo) values ('mensal', 'Mensal', 30, 'Acesso por 30 dias.', 1, true) on conflict (id) do nothing;
insert into planos (id, nome, duracao_dias, descricao, ordem, ativo) values ('trimestral', 'Trimestral', 90, 'Acesso por 90 dias.', 2, true) on conflict (id) do nothing;
insert into planos (id, nome, duracao_dias, descricao, ordem, ativo) values ('semestral', 'Semestral', 180, 'Acesso por 180 dias.', 3, true) on conflict (id) do nothing;
insert into planos (id, nome, duracao_dias, descricao, ordem, ativo) values ('anual', 'Anual', 365, 'Acesso por 365 dias.', 4, true) on conflict (id) do nothing;

-- Unidades --------------------------------------------------------------------
insert into unidades (id, rotulo, abreviacao, singular, continua, ordem) values ('g', 'Gramas', 'g', 'g', true, 0) on conflict (id) do nothing;
insert into unidades (id, rotulo, abreviacao, singular, continua, ordem) values ('ml', 'Mililitros', 'ml', 'ml', true, 1) on conflict (id) do nothing;
insert into unidades (id, rotulo, abreviacao, singular, continua, ordem) values ('unidade', 'Unidades', 'un', 'unidade', false, 2) on conflict (id) do nothing;
insert into unidades (id, rotulo, abreviacao, singular, continua, ordem) values ('fatia', 'Fatias', 'fatias', 'fatia', false, 3) on conflict (id) do nothing;
insert into unidades (id, rotulo, abreviacao, singular, continua, ordem) values ('colher-sopa', 'Colheres de sopa', 'col. sopa', 'colher de sopa', false, 4) on conflict (id) do nothing;
insert into unidades (id, rotulo, abreviacao, singular, continua, ordem) values ('colher-cha', 'Colheres de chá', 'col. chá', 'colher de chá', false, 5) on conflict (id) do nothing;
insert into unidades (id, rotulo, abreviacao, singular, continua, ordem) values ('xicara', 'Xícaras', 'xíc.', 'xícara', false, 6) on conflict (id) do nothing;
insert into unidades (id, rotulo, abreviacao, singular, continua, ordem) values ('concha', 'Conchas', 'conchas', 'concha', false, 7) on conflict (id) do nothing;

-- Grupos alimentares ----------------------------------------------------------
insert into grupos_alimentares (id, nome, descricao, ordem, regra, troca_por_porcao, troca_para_grupos, tags) values ('carboidratos', 'Carboidratos', 'Arroz, massas, tubérculos, pães e raízes.', 1, '{"tipo":"porcoes"}'::jsonb, true, array['frutas']::text[], array['carboidrato', 'massa', 'arroz', 'pao', 'tuberculo']::text[]) on conflict (id) do nothing;
insert into grupos_alimentares (id, nome, descricao, ordem, regra, troca_por_porcao, troca_para_grupos, tags) values ('proteinas', 'Proteínas', 'Carnes, ovos, peixes e outras fontes proteicas.', 2, '{"tipo":"porcoes"}'::jsonb, true, '{}'::text[], array['proteina', 'carne', 'ovo', 'peixe', 'frango']::text[]) on conflict (id) do nothing;
insert into grupos_alimentares (id, nome, descricao, ordem, regra, troca_por_porcao, troca_para_grupos, tags) values ('gorduras', 'Gorduras', 'Azeites, oleaginosas, abacate e similares.', 3, '{"tipo":"porcoes"}'::jsonb, true, '{}'::text[], array['gordura', 'azeite', 'castanha', 'abacate']::text[]) on conflict (id) do nothing;
insert into grupos_alimentares (id, nome, descricao, ordem, regra, troca_por_porcao, troca_para_grupos, tags) values ('frutas', 'Frutas', 'Frutas in natura e suas porções.', 4, '{"tipo":"porcoes"}'::jsonb, true, '{}'::text[], array['fruta']::text[]) on conflict (id) do nothing;
insert into grupos_alimentares (id, nome, descricao, ordem, regra, troca_por_porcao, troca_para_grupos, tags) values ('vegetais-livres', 'Vegetais livres', 'Quantidade livre, respeitando a porção mínima das refeições principais.', 5, '{"tipo":"livre","minimos":[{"refeicao":"Almoço","medida":{"quantidade":150,"unidadeId":"g"}},{"refeicao":"Jantar","medida":{"quantidade":150,"unidadeId":"g"}}],"texto":"Quantidade livre. No almoço e no jantar, a porção mínima é de 150 g."}'::jsonb, false, '{}'::text[], array['vegetal', 'legume', 'verdura', 'salada', 'livre']::text[]) on conflict (id) do nothing;
insert into grupos_alimentares (id, nome, descricao, ordem, regra, troca_por_porcao, troca_para_grupos, tags) values ('outros', 'Outros', 'Itens que não se encaixam nos grupos acima.', 6, null, false, '{}'::text[], array['outros']::text[]) on conflict (id) do nothing;

-- Alimentos -------------------------------------------------------------------
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('achocolatado-em-po', 'Achocolatado em pó', 'carboidratos', 'g', 30, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('achocolatado-em-po-light-ou-com-maior-teor-de', 'Achocolatado em pó light ou com maior teor de cacau', 'carboidratos', 'g', 35, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('abobora-crua', 'Abóbora crua', 'carboidratos', 'g', 320, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('abobora-cozida', 'Abóbora cozida', 'carboidratos', 'g', 260, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('amaranto', 'Amaranto', 'carboidratos', 'g', 120, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('arroz-cozido', 'Arroz integral ou branco cozido', 'carboidratos', 'g', 100, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('arroz-integral-ou-branco-cru', 'Arroz integral ou branco cru', 'carboidratos', 'g', 35, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('aveia-em-flocos', 'Aveia em flocos', 'carboidratos', 'g', 30, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Pode fermentar e causar desconforto gástrico.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('aveia-em-farelo-ou-farinha', 'Aveia em farelo ou farinha', 'carboidratos', 'g', 50, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Pode fermentar e causar desconforto gástrico.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('batata-baroa-ou-mandioquinha-cozida', 'Batata baroa ou mandioquinha cozida', 'carboidratos', 'g', 150, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('batata-doce-crua', 'Batata doce crua', 'carboidratos', 'g', 105, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Pode fermentar e causar desconforto gástrico.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('batata-doce-cozida', 'Batata doce cozida', 'carboidratos', 'g', 160, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Pode fermentar e causar desconforto gástrico.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('batata-cozida', 'Batata inglesa cozida ou crua', 'carboidratos', 'g', 145, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('biscoito-de-arroz', 'Biscoito de arroz', 'carboidratos', 'g', 30, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('biscoito-de-maizena', 'Biscoito de maizena', 'carboidratos', 'g', 25, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('biscoito-de-polvilho', 'Biscoito de polvilho', 'carboidratos', 'g', 30, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('bolo-ou-broa', 'Bolo ou broa', 'carboidratos', 'g', 50, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Sem calda e sem recheio.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('cara-cozido', 'Cará cozido', 'carboidratos', 'g', 160, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('caldo-de-cana', 'Caldo de cana', 'carboidratos', 'g', 160, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('cereal-matinal', 'Cereal matinal', 'carboidratos', 'g', 30, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('chocolate-ao-leite', 'Chocolate ao leite', 'carboidratos', 'g', 20, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('chocolate-branco', 'Chocolate branco', 'carboidratos', 'g', 20, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('creme-de-arroz-em-po', 'Creme de arroz em pó', 'carboidratos', 'g', 30, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('cuscuz-cru', 'Cuscuz cru', 'carboidratos', 'g', 35, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Mesmo valor do floco de milho.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('cuscuz-marroquino', 'Cuscuz marroquino', 'carboidratos', 'g', 35, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Mesmo valor da semolina.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('doce-de-leite', 'Doce de leite', 'carboidratos', 'g', 35, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Prefira a versão com o mínimo de ingredientes possível.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('edamame', 'Edamame', 'carboidratos', 'g', 100, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Pode fermentar e causar desconforto gástrico.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('ervilha-cozida', 'Ervilha cozida', 'carboidratos', 'g', 150, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('farinha-de-arroz', 'Farinha de arroz', 'carboidratos', 'g', 30, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Pode fermentar e causar desconforto gástrico.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('farinha-de-batata-doce', 'Farinha de batata doce', 'carboidratos', 'g', 40, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Pode fermentar e causar desconforto gástrico.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('farinha-de-grao-de-bico', 'Farinha de grão-de-bico', 'carboidratos', 'g', 50, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Pode fermentar e causar desconforto gástrico.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('farinha-de-mandioca', 'Farinha de mandioca', 'carboidratos', 'g', 35, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('farinha-de-milho', 'Farinha de milho', 'carboidratos', 'g', 35, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('farinha-panko', 'Farinha panko', 'carboidratos', 'g', 40, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('farinha-de-teff', 'Farinha de teff', 'carboidratos', 'g', 35, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('feijao-cozido', 'Feijão cozido', 'carboidratos', 'g', 160, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Pode fermentar e causar desconforto gástrico.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('flocos-de-arroz', 'Flocos de arroz', 'carboidratos', 'g', 35, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('folha-ou-papel-de-arroz', 'Folha ou papel de arroz', 'carboidratos', 'g', 35, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('fuba', 'Fubá', 'carboidratos', 'g', 35, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('grao-de-bico-cozido', 'Grão-de-bico cozido', 'carboidratos', 'g', 75, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Pode fermentar e causar desconforto gástrico.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('goiabada-ou-qualquer-outro-doce-de-fruta', 'Goiabada ou qualquer outro doce de fruta', 'carboidratos', 'g', 50, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Prefira a versão com o mínimo de ingredientes possível.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('granola-sem-acucar', 'Granola sem açúcar', 'carboidratos', 'g', 30, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('inhame-cozido', 'Inhame cozido', 'carboidratos', 'g', 90, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('lentilha-cozida', 'Lentilha cozida', 'carboidratos', 'g', 130, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Pode fermentar e causar desconforto gástrico.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('leite-condensado', 'Leite condensado', 'carboidratos', 'g', 40, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('leite-condensado-light', 'Leite condensado light', 'carboidratos', 'g', 45, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('leite-de-arroz', 'Leite de arroz', 'carboidratos', 'g', 260, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Mínimo de ingredientes possível e sem açúcar.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('leite-de-aveia', 'Leite de aveia', 'carboidratos', 'g', 300, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Mínimo de ingredientes possível e sem açúcar.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('leite-de-soja', 'Leite de soja', 'carboidratos', 'g', 230, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('mandioca-cozida', 'Mandioca cozida', 'carboidratos', 'g', 100, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('macarrao-bifun', 'Macarrão bifun', 'carboidratos', 'g', 35, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('macarrao-cozido', 'Macarrão com ou sem glúten cozido', 'carboidratos', 'g', 80, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('mel', 'Mel', 'carboidratos', 'g', 30, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('melado', 'Melado', 'carboidratos', 'g', 30, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('milho-cozido', 'Milho cozido', 'carboidratos', 'g', 100, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('milho-cru', 'Milho cru', 'carboidratos', 'g', 90, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('nutella', 'Nutella', 'carboidratos', 'g', 20, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('nescau-60-menos-acucar', 'Nescau 60% menos açúcar', 'carboidratos', 'g', 40, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('pao', 'Pão com ou sem glúten', 'carboidratos', 'g', 50, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Prefira a versão com o mínimo de ingredientes possível.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('pudim', 'Pudim', 'carboidratos', 'g', 55, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('puff-de-trigo', 'Puff de trigo', 'carboidratos', 'g', 35, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('polvilho-azedo-ou-doce', 'Polvilho azedo ou doce', 'carboidratos', 'g', 35, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('wrap-com-ou-sem-gluten', 'Wrap com ou sem glúten', 'carboidratos', 'g', 50, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Prefira a versão com o mínimo de ingredientes possível.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('suco-integral-sem-acucar', 'Suco integral sem açúcar', 'carboidratos', 'g', 260, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Mínimo de ingredientes possível e sem açúcar.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('soja-em-graos-cozida', 'Soja em grãos cozida', 'carboidratos', 'g', 70, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Pode fermentar e causar desconforto gástrico.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('quinoa-cozida', 'Quinoa cozida', 'carboidratos', 'g', 100, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Pode fermentar e causar desconforto gástrico.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('tapioca', 'Tapioca', 'carboidratos', 'g', 45, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('acem', 'Acém', 'proteinas', 'g', 70, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('atum-cozido-em-lata-ou-grelhado', 'Atum cozido em lata ou grelhado', 'proteinas', 'g', 110, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('atum-cru', 'Atum cru', 'proteinas', 'g', 100, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('camarao-e-outros-frutos-do-mar', 'Camarão e outros frutos do mar', 'proteinas', 'g', 160, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('clara-de-ovo', 'Clara de ovo', 'proteinas', 'unidade', 9, 'unidade', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('clara-de-ovo-de-codorna', 'Clara de ovo de codorna', 'proteinas', 'unidade', 27, 'unidade', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('claras-pasteurizadas', 'Claras pasteurizadas', 'proteinas', 'g', 330, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Prefira a versão com o mínimo de ingredientes possível.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('creme-de-ricota-light-com-ou-sem-lactose', 'Creme de ricota light com ou sem lactose', 'proteinas', 'g', 100, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Prefira a versão com o mínimo de ingredientes possível.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('coalhada-desnatada-com-ou-sem-lactose', 'Coalhada desnatada com ou sem lactose', 'proteinas', 'g', 250, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Mínimo de ingredientes possível, sem açúcar e sem sabor. Adoçantes naturais: stevia, taumatina, eritritol. Evitar sucralose, acessulfame K, aspartame, acessulfame de potássio, ciclamato e xilitol.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('coracao-de-galinha', 'Coração de galinha', 'proteinas', 'g', 90, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('coxao-duro', 'Coxão duro', 'proteinas', 'g', 70, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('cupim', 'Cupim', 'proteinas', 'g', 70, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('frango-coxa-e-sobrecoxa-desossada', 'Frango coxa e sobrecoxa desossada', 'proteinas', 'g', 60, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('frango-peito', 'Frango peito', 'proteinas', 'g', 100, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('fraldinha', 'Fraldinha', 'proteinas', 'g', 60, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('figado', 'Fígado', 'proteinas', 'g', 75, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('file-mignon', 'Filé mignon', 'proteinas', 'g', 70, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('iogurte-desnatado-de-2-ingredientes-ou-0-de', 'Iogurte desnatado de 2 ingredientes ou 0% de gordura com ou sem lactose', 'proteinas', 'g', 250, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Mínimo de ingredientes possível, sem açúcar e sem sabor. Adoçantes naturais: stevia, taumatina, eritritol. Evitar sucralose, acessulfame K, aspartame, acessulfame de potássio, ciclamato e xilitol.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('kefir-desnatado-com-ou-sem-lactose', 'Kefir desnatado com ou sem lactose', 'proteinas', 'g', 430, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Mínimo de ingredientes possível, sem açúcar e sem sabor. Adoçantes naturais: stevia, taumatina, eritritol. Evitar sucralose, acessulfame K, aspartame, acessulfame de potássio, ciclamato e xilitol.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('musculo-bovino', 'Músculo bovino', 'proteinas', 'g', 80, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('patinho', 'Patinho', 'proteinas', 'g', 70, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('peixe-branco', 'Peixe branco', 'proteinas', 'g', 140, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('peru', 'Peru', 'proteinas', 'g', 100, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('picanha', 'Picanha', 'proteinas', 'g', 70, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('proteina-texturizada-da-soja-organica-pts', 'Proteína texturizada da soja orgânica (PTS) crua ou hidratada', 'proteinas', 'g', 60, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('proteina-em-po-albumina-beef-protein-clara-de', 'Proteína em pó (albumina, beef protein, clara de ovo em pó, colágeno, proteína vegetal, whey)', 'proteinas', 'g', 40, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Mínimo de ingredientes possível, sem açúcar e sem sabor. Adoçantes naturais: stevia, taumatina, eritritol. Evitar sucralose, acessulfame K, aspartame, acessulfame de potássio, ciclamato e xilitol.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('polenghi-light-com-ou-sem-lactose', 'Polenghi light com ou sem lactose', 'proteinas', 'g', 90, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('polenghi-frescatino-ultrafiltrado-com-ou-sem', 'Polenghi Frescatino ultrafiltrado com ou sem lactose', 'proteinas', 'g', 70, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('polenghi-frescatino-ultrafiltrado-light-com', 'Polenghi Frescatino ultrafiltrado light com ou sem lactose', 'proteinas', 'g', 100, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('polenghi-queijo-frescal-ultrafiltrado-light', 'Polenghi queijo frescal ultrafiltrado light com ou sem lactose', 'proteinas', 'g', 100, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('queijo-cottage-de-vaca-ou-de-bufala-com-ou', 'Queijo cottage de vaca ou de búfala com ou sem lactose', 'proteinas', 'g', 150, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('queijo-ricota-fresca-com-12-de-gordura-ou', 'Queijo ricota fresca com 12% de gordura ou menos com ou sem lactose', 'proteinas', 'g', 100, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('queijo-minas-frescal-light-com-ou-sem-lactose', 'Queijo minas frescal light com ou sem lactose', 'proteinas', 'g', 85, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('queijo-parmesao-light-com-ou-sem-lactose', 'Queijo parmesão light com ou sem lactose', 'proteinas', 'g', 50, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('queijo-de-soro-de-leite-com-ou-sem-lactose', 'Queijo de soro de leite com ou sem lactose', 'proteinas', 'g', 75, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('queijo-quark-light-com-ou-sem-lactose', 'Queijo quark light com ou sem lactose', 'proteinas', 'g', 95, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('salmao', 'Salmão', 'proteinas', 'g', 60, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('salmao-cru', 'Salmão cru', 'proteinas', 'g', 85, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('sardinha-em-lata', 'Sardinha em lata', 'proteinas', 'g', 80, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('suino-lombo', 'Suíno lombo', 'proteinas', 'g', 70, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('suino-file-mignon', 'Suíno filé mignon', 'proteinas', 'g', 100, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('suino-pernil', 'Suíno pernil', 'proteinas', 'g', 55, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('tempeh-organico', 'Tempeh orgânico', 'proteinas', 'g', 75, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('tofu-organico', 'Tofu orgânico', 'proteinas', 'g', 200, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('abacate-ou-avocado', 'Abacate ou avocado', 'gorduras', 'g', 60, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Pode fermentar e causar desconforto gástrico.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('amendoas', 'Amêndoas', 'gorduras', 'g', 15, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('amendoim-cru', 'Amendoim cru', 'gorduras', 'g', 15, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Pode fermentar e causar desconforto gástrico.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('avela', 'Avelã', 'gorduras', 'g', 13, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('azeite', 'Azeite', 'gorduras', 'g', 10, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('azeitona', 'Azeitona', 'gorduras', 'g', 75, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('cafes-termogenicos', 'Cafés termogênicos', 'gorduras', 'g', 20, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('castanhas', 'Castanhas', 'gorduras', 'g', 15, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('chocolate-60-ou-mais', 'Chocolate 60% ou mais', 'gorduras', 'g', 15, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('coalhada-com-ou-sem-lactose', 'Coalhada com ou sem lactose', 'gorduras', 'g', 90, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Mínimo de ingredientes possível, sem açúcar e sem sabor. Adoçantes naturais: stevia, taumatina, eritritol. Evitar sucralose, acessulfame K, aspartame, acessulfame de potássio, ciclamato e xilitol.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('coco-em-lascas-ou-desidratado', 'Coco em lascas ou desidratado', 'gorduras', 'g', 15, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('coco-em-pedacos', 'Coco em pedaços', 'gorduras', 'g', 25, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'O da casca marrom.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('creme-de-castanha-de-caju', 'Creme de castanha de caju', 'gorduras', 'g', 30, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Prefira a versão com o mínimo de ingredientes possível.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('creme-de-leite-com-ou-sem-lactose', 'Creme de leite com ou sem lactose', 'gorduras', 'g', 30, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Melhor opção: o fresco, em garrafinha ou latinha.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('creme-de-ricota-original-com-ou-sem-lactose', 'Creme de ricota original com ou sem lactose', 'gorduras', 'g', 45, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Prefira a versão com o mínimo de ingredientes possível.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('creme-de-queijo-minas-frescal-com-ou-sem', 'Creme de queijo minas frescal com ou sem lactose', 'gorduras', 'g', 30, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Prefira a versão com o mínimo de ingredientes possível.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('creme-de-queijo-minas-frescal-light-com-ou', 'Creme de queijo minas frescal light com ou sem lactose', 'gorduras', 'g', 45, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Prefira a versão com o mínimo de ingredientes possível.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('cream-cheese-com-ou-sem-lactose', 'Cream cheese com ou sem lactose', 'gorduras', 'g', 30, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Prefira a versão com o mínimo de ingredientes possível.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('cream-cheese-light-com-ou-sem-lactose', 'Cream cheese light com ou sem lactose', 'gorduras', 'g', 40, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Prefira a versão com o mínimo de ingredientes possível.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('farinha-de-amendoas', 'Farinha de amêndoas', 'gorduras', 'g', 15, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('farinha-de-coco', 'Farinha de coco', 'gorduras', 'g', 15, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('farinha-de-linhaca', 'Farinha de linhaça', 'gorduras', 'g', 15, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('gema-ou-ovo-inteiro', 'Gema ou ovo inteiro', 'gorduras', 'unidade', 1, 'unidade', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('iogurte-de-2-ou-3-ingredientes-com-ou-sem', 'Iogurte de 2 ou 3 ingredientes com ou sem lactose', 'gorduras', 'g', 140, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Mínimo de ingredientes possível, sem açúcar e sem sabor. Adoçantes naturais: stevia, taumatina, eritritol. Evitar sucralose, acessulfame K, aspartame, acessulfame de potássio, ciclamato e xilitol.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('kefir-integral-com-ou-sem-lactose', 'Kefir integral com ou sem lactose', 'gorduras', 'g', 135, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Mínimo de ingredientes possível, sem açúcar e sem sabor. Adoçantes naturais: stevia, taumatina, eritritol. Evitar sucralose, acessulfame K, aspartame, acessulfame de potássio, ciclamato e xilitol.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('leite-integral-com-ou-sem-lactose', 'Leite integral com ou sem lactose', 'gorduras', 'ml', 130, 'ml', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('leite-desnatado-ou-semidesnatado-com-ou-sem', 'Leite desnatado ou semidesnatado com ou sem lactose', 'gorduras', 'ml', 260, 'ml', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('leite-em-po-com-ou-sem-lactose-ou-leite-de', 'Leite em pó com ou sem lactose ou leite de coco em pó', 'gorduras', 'g', 15, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Mínimo de ingredientes possível e sem açúcar.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('leite-em-po-desnatado-com-ou-sem-lactose', 'Leite em pó desnatado com ou sem lactose', 'gorduras', 'g', 25, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Mínimo de ingredientes possível e sem açúcar.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('leite-vegetal-amendoas-coco-castanha-de-caju', 'Leite vegetal (amêndoas, coco, castanha de caju e outros)', 'gorduras', 'ml', 300, 'ml', false, '[]'::jsonb, null, null, '{}'::text[], 'Mínimo de ingredientes possível e sem açúcar.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('macadamia', 'Macadâmia', 'gorduras', 'g', 10, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('manteiga', 'Manteiga', 'gorduras', 'g', 10, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('manteiga-de-bufala', 'Manteiga de búfala', 'gorduras', 'g', 10, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('manteiga-de-coco', 'Manteiga de coco', 'gorduras', 'g', 10, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('manteiga-ghee', 'Manteiga ghee', 'gorduras', 'g', 10, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('manteiga-vegana', 'Manteiga vegana', 'gorduras', 'g', 10, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('mct-ou-tcm', 'MCT ou TCM', 'gorduras', 'g', 10, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('nozes', 'Nozes', 'gorduras', 'g', 15, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('oleo-de-coco', 'Óleo de coco', 'gorduras', 'g', 10, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('ovo-de-codorna-inteiro', 'Ovo de codorna inteiro', 'gorduras', 'unidade', 5, 'unidade', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('pasta-de-amendoim-avela-amendoas-castanha-de', 'Pasta de amendoim, avelã, amêndoas, castanha de caju, macadâmia e outras', 'gorduras', 'g', 15, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Mínimo de ingredientes possível, sem açúcar e sem sabor. Adoçantes naturais: stevia, taumatina, eritritol. Evitar sucralose, acessulfame K, aspartame, acessulfame de potássio, ciclamato e xilitol.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('pacoca', 'Paçoca', 'gorduras', 'g', 15, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('pistache-torrado', 'Pistache torrado', 'gorduras', 'g', 15, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('polenguinho', 'Polenguinho', 'gorduras', 'g', 35, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('queijo-brie-ou-queijo-de-cabra-com-ou-sem', 'Queijo brie ou queijo de cabra com ou sem lactose', 'gorduras', 'g', 25, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('queijo-burrata-com-ou-sem-lactose', 'Queijo burrata com ou sem lactose', 'gorduras', 'g', 30, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('queijo-coalho-normal-ou-light-com-ou-sem', 'Queijo coalho, normal ou light, com ou sem lactose', 'gorduras', 'g', 25, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('queijo-canastra-com-ou-sem-lactose', 'Queijo canastra com ou sem lactose', 'gorduras', 'g', 20, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('queijo-curado-com-ou-sem-lactose', 'Queijo curado com ou sem lactose', 'gorduras', 'g', 20, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('queijo-gorgonzola-com-ou-sem-lactose', 'Queijo gorgonzola com ou sem lactose', 'gorduras', 'g', 25, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('queijo-meia-cura-com-ou-sem-lactose', 'Queijo meia cura com ou sem lactose', 'gorduras', 'g', 25, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('queijo-minas-frescal-com-ou-sem-lactose', 'Queijo minas frescal com ou sem lactose', 'gorduras', 'g', 35, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('queijo-minas-padrao-com-ou-sem-lactose', 'Queijo minas padrão com ou sem lactose', 'gorduras', 'g', 30, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('queijo-mussarela-ou-de-bufala-normal-ou-light', 'Queijo mussarela ou de búfala, normal ou light, com ou sem lactose', 'gorduras', 'g', 30, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('queijo-parmesao-com-ou-sem-lactose', 'Queijo parmesão com ou sem lactose', 'gorduras', 'g', 20, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('queijo-prato-com-ou-sem-lactose', 'Queijo prato com ou sem lactose', 'gorduras', 'g', 20, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('queijo-ricota-fresca-com-mais-de-12-de', 'Queijo ricota fresca com mais de 12% de gordura com ou sem lactose', 'gorduras', 'g', 60, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('requeijao-com-ou-sem-lactose', 'Requeijão com ou sem lactose', 'gorduras', 'g', 35, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Prefira a versão com o mínimo de ingredientes possível.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('requeijao-light-com-ou-sem-lactose', 'Requeijão light com ou sem lactose', 'gorduras', 'g', 50, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Prefira a versão com o mínimo de ingredientes possível.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('requeijao-vegano', 'Requeijão vegano', 'gorduras', 'g', 30, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Prefira a versão com o mínimo de ingredientes possível.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('sementes', 'Sementes', 'gorduras', 'g', 15, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Inclui chia e todos os tipos, sem exceção.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('tahine', 'Tahine', 'gorduras', 'g', 10, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Prefira a versão com o mínimo de ingredientes possível.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('abacaxi', 'Abacaxi', 'frutas', 'g', 200, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('acai-polpa-pura-sem-acucar', 'Açaí polpa pura sem açúcar', 'frutas', 'g', 175, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Únicos ingredientes: polpa de açaí e água. Sem açúcar e sem sabor. Adoçantes naturais: stevia, taumatina, eritritol. Evitar sucralose, acessulfame K, aspartame, acessulfame de potássio, ciclamato e xilitol.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('acerola', 'Acerola', 'frutas', 'g', 310, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('agua-de-coco-in-natura', 'Água de coco in natura', 'frutas', 'ml', 500, 'ml', false, '[]'::jsonb, null, null, '{}'::text[], 'Pode fermentar e causar desconforto gástrico.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('ameixa', 'Ameixa', 'frutas', 'g', 210, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('ameixa-seca', 'Ameixa seca', 'frutas', 'g', 40, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Mínimo de ingredientes possível e sem açúcar. Pode fermentar e causar desconforto gástrico.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('amora', 'Amora', 'frutas', 'g', 230, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('atemoia', 'Atemóia', 'frutas', 'g', 100, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('banana-da-terra', 'Banana da terra', 'frutas', 'g', 80, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('banana', 'Banana', 'frutas', 'g', 90, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('banana-chips', 'Banana chips', 'frutas', 'g', 20, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Mínimo de ingredientes possível e sem açúcar.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('blueberry-ou-mirtilo', 'Blueberry ou mirtilo', 'frutas', 'g', 175, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('caja-manga', 'Cajá-manga', 'frutas', 'g', 220, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('caju', 'Caju', 'frutas', 'g', 230, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('caqui', 'Caqui', 'frutas', 'g', 80, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('carambola', 'Carambola', 'frutas', 'g', 320, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('cereja', 'Cereja', 'frutas', 'g', 200, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('ciriguela', 'Ciriguela', 'frutas', 'g', 125, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('cranberry', 'Cranberry', 'frutas', 'g', 30, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('cupuacu', 'Cupuaçu', 'frutas', 'g', 200, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('damasco-seco', 'Damasco seco', 'frutas', 'g', 40, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Mínimo de ingredientes possível e sem açúcar. Pode fermentar e causar desconforto gástrico.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('figo', 'Figo', 'frutas', 'g', 135, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('figo-seco', 'Figo seco', 'frutas', 'g', 40, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Mínimo de ingredientes possível e sem açúcar. Pode fermentar e causar desconforto gástrico.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('framboesa', 'Framboesa', 'frutas', 'g', 180, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('geleia-100-fruta', 'Geleia 100% fruta', 'frutas', 'g', 55, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Mínimo de ingredientes possível, sem açúcar e sem sabor. Adoçantes naturais: stevia, taumatina, eritritol. Evitar sucralose, acessulfame K, aspartame, acessulfame de potássio, ciclamato e xilitol.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('goiaba', 'Goiaba', 'frutas', 'g', 150, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('graviola', 'Graviola', 'frutas', 'g', 150, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('jabuticaba', 'Jabuticaba', 'frutas', 'g', 170, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('jaca', 'Jaca', 'frutas', 'g', 105, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('jambo', 'Jambo', 'frutas', 'g', 200, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('kiwi', 'Kiwi', 'frutas', 'g', 160, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('laranja', 'Laranja', 'frutas', 'g', 210, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('lichia', 'Lichia', 'frutas', 'g', 140, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('limao', 'Limão', 'frutas', 'g', null, null, true, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('maca', 'Maçã', 'frutas', 'g', 190, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('mamao', 'Mamão', 'frutas', 'g', 230, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('manga', 'Manga', 'frutas', 'g', 160, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('maracuja', 'Maracujá', 'frutas', 'g', 140, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('melancia', 'Melancia', 'frutas', 'g', 330, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('melao', 'Melão', 'frutas', 'g', 340, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('mexerica-ou-tangerina', 'Mexerica ou tangerina', 'frutas', 'g', 200, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('morango', 'Morango', 'frutas', 'g', 300, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('nespera', 'Nêspera', 'frutas', 'g', 210, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('pera', 'Pêra', 'frutas', 'g', 175, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('pessego', 'Pêssego', 'frutas', 'g', 250, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('pinha-ou-fruta-do-conde', 'Pinha ou fruta do conde', 'frutas', 'g', 125, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('pitanga', 'Pitanga', 'frutas', 'g', 300, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('pitaya', 'Pitaya', 'frutas', 'g', 165, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('roma', 'Romã', 'frutas', 'g', 200, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('tamarindo', 'Tamarindo', 'frutas', 'g', 30, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('tamara-seca', 'Tâmara seca', 'frutas', 'g', 35, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Mínimo de ingredientes possível e sem açúcar. Pode fermentar e causar desconforto gástrico.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('tucuma', 'Tucumã', 'frutas', 'g', 35, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('uva-verde-ou-roxa-sem-caroco', 'Uva verde ou roxa sem caroço', 'frutas', 'g', 180, 'g', false, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('uva-passas', 'Uva passas', 'frutas', 'g', 30, 'g', false, '[]'::jsonb, null, null, '{}'::text[], 'Mínimo de ingredientes possível e sem açúcar. Pode fermentar e causar desconforto gástrico.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('abobrinha', 'Abobrinha', 'vegetais-livres', 'g', null, null, true, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('aspargos', 'Aspargos', 'vegetais-livres', 'g', null, null, true, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('alho', 'Alho', 'vegetais-livres', 'g', null, null, true, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('alho-poro', 'Alho-poró', 'vegetais-livres', 'g', null, null, true, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('berinjela', 'Berinjela', 'vegetais-livres', 'g', null, null, true, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('beterraba', 'Beterraba', 'vegetais-livres', 'g', null, null, true, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('brocolis', 'Brócolis', 'vegetais-livres', 'g', null, null, true, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('cebola', 'Cebola', 'vegetais-livres', 'g', null, null, true, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('cenoura', 'Cenoura', 'vegetais-livres', 'g', null, null, true, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('chuchu', 'Chuchu', 'vegetais-livres', 'g', null, null, true, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('cogumelos', 'Cogumelos', 'vegetais-livres', 'g', null, null, true, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('couve-flor', 'Couve-flor', 'vegetais-livres', 'g', null, null, true, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('couve-de-bruxelas', 'Couve-de-bruxelas', 'vegetais-livres', 'g', null, null, true, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('ervilha-torta', 'Ervilha-torta', 'vegetais-livres', 'g', null, null, true, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('jilo', 'Jiló', 'vegetais-livres', 'g', null, null, true, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('maxixe', 'Maxixe', 'vegetais-livres', 'g', null, null, true, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('nabo', 'Nabo', 'vegetais-livres', 'g', null, null, true, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('palmito', 'Palmito', 'vegetais-livres', 'g', null, null, true, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('pimentao', 'Pimentão', 'vegetais-livres', 'g', null, null, true, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('pepino', 'Pepino', 'vegetais-livres', 'g', null, null, true, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('repolho', 'Repolho', 'vegetais-livres', 'g', null, null, true, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('quiabo', 'Quiabo', 'vegetais-livres', 'g', null, null, true, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('rabanete', 'Rabanete', 'vegetais-livres', 'g', null, null, true, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('tomate', 'Tomate', 'vegetais-livres', 'g', null, null, true, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('tomatinho', 'Tomatinho', 'vegetais-livres', 'g', null, null, true, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('vagem', 'Vagem', 'vegetais-livres', 'g', null, null, true, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, quantidade_livre, medidas, sem_gluten, sem_lactose, tags, observacao) values ('folhas-e-brotos', 'Folhas e brotos', 'vegetais-livres', 'g', null, null, true, '[]'::jsonb, null, null, '{}'::text[], null) on conflict (id) do nothing;

-- Equivalências ---------------------------------------------------------------
insert into equivalencias (id, origem_alimento_id, destino_alimento_id, tipo, regra, bidirecional, fonte, observacao) values ('arroz-para-macarrao', 'arroz-cozido', 'macarrao-cozido', 'proporcional', '{"tipo":"proporcional","de":{"quantidade":100,"unidadeId":"g"},"para":{"quantidade":80,"unidadeId":"g"}}'::jsonb, true, 'Lista de substituição', null) on conflict (id) do nothing;

-- Comer fora ------------------------------------------------------------------
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('hamburguer', 'comer_fora', 'Hambúrguer', null, 'Como montar o lanche do jeito que cabe no seu dia.', 'hamburguer', 1, 'publicado', '{"introducao":"Escolha o lugar e veja o que pedir. A diferença entre uma opção e outra costuma estar nos acompanhamentos, não no lanche em si.","decisoes":[],"lembretes":[]}'::jsonb, array['hamburguer', 'lanche', 'burger']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('japonesa', 'comer_fora', 'Comida japonesa', null, 'Entradas, combinados e o que costuma pesar no rodízio.', 'japonesa', 2, 'publicado', '{"introducao":"Comece pelas entradas, escolha o combinado e deixe as preparações fritas e os molhos cremosos como parte menor da refeição.","decisoes":[],"lembretes":[]}'::jsonb, array['japonesa', 'japones', 'sushi', 'sashimi', 'rodizio', 'temaki']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('massas', 'comer_fora', 'Massas', null, 'Quantidade da massa, proteína e molho.', 'massas', 3, 'publicado', '{"introducao":"Três escolhas definem o prato: quanto de massa, se entra proteína e qual molho acompanha.","decisoes":[],"lembretes":["Prefira o molho ao sugo.","Adicione proteína para trazer mais saciedade: massa e frango, massa e camarão, massa e carne magra."]}'::jsonb, array['massa', 'macarrao', 'italiano', 'molho', 'spoleto', 'lasanha']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('pizza', 'comer_fora', 'Pizza', null, 'Quantas fatias fecham uma refeição, por tipo de massa.', 'pizza', 4, 'publicado', '{"introducao":"A conta muda com a massa: quanto mais densa, menos fatias fecham a mesma refeição.","decisoes":[],"lembretes":["Prefira opções com proteína e sem muita adição de queijo, como frango ou carne seca."]}'::jsonb, array['pizza', 'pizzaria', 'fatia', 'borda']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('acai', 'comer_fora', 'Açaí', null, 'Tamanho da tigela e o que entra junto.', 'acai', 5, 'publicado', '{"introducao":"O tamanho decide se o açaí é a refeição livre inteira ou metade dela.","decisoes":[],"lembretes":[]}'::jsonb, array['acai', 'tigela', 'copo']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('doces', 'comer_fora', 'Doces e sobremesas', null, 'Cada uma destas conta como meia refeição livre.', 'doces', 6, 'publicado', '{"introducao":"Duas destas opções somam uma refeição livre completa.","decisoes":[{"id":"sobremesas","titulo":"Meias refeições doces","pergunta":"O que está na mesa?","observacoes":[],"opcoes":[{"id":"doce-gelato","titulo":"Gelato: 1 copo médio com 2 sabores","descricao":"Bacio di Latte, Lullo, Mi Garba.","nivel":null,"energia":null,"detalhes":[],"tags":["gelato","sorvete"]},{"id":"doce-cookie","titulo":"1 cookie artesanal grande, estilo americano","descricao":"Mr. Cheney, American Day.","nivel":null,"energia":null,"detalhes":[],"tags":["cookie"]},{"id":"doce-bolo","titulo":"1 fatia média de bolo ou torta com calda","descricao":null,"nivel":null,"energia":null,"detalhes":[],"tags":["bolo","torta"]},{"id":"doce-brownie","titulo":"1 brownie com 1 bola de sorvete","descricao":null,"nivel":null,"energia":null,"detalhes":[],"tags":["brownie","sorvete"]},{"id":"doce-milkshake","titulo":"Milkshake pequeno","descricao":"Bob''s, McDonald''s.","nivel":null,"energia":{"kcal":330,"mostrarKcal":false,"observacao":null},"detalhes":[],"tags":["milkshake"]},{"id":"doce-acai","titulo":"Açaí de 300 ml com 1 fruta e leite condensado","descricao":null,"nivel":null,"energia":null,"detalhes":[],"tags":["acai"]}]}],"lembretes":[]}'::jsonb, array['doce', 'sobremesa', 'chocolate', 'bolo', 'sorvete', 'cookie']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('barzinho', 'comer_fora', 'Barzinho', null, 'O que pedir para beber, e o que costuma acompanhar.', 'taca', 7, 'publicado', '{"introducao":"As contas abaixo são para duas doses — é o mínimo que costuma acontecer numa saída. Os números são estimativa: bar não publica tabela, e a receita muda de casa para casa.","decisoes":[{"id":"com-drink","titulo":"Com drink","pergunta":"Duas doses, mais o que vem para beliscar.","observacoes":[],"opcoes":[{"id":"drink-melhor","titulo":"Caipirinha, vodka soda ou Moscow Mule","descricao":"Duas doses, com porção pequena de azeitonas ou castanhas.","nivel":"melhor","energia":{"kcal":450,"mostrarKcal":true,"observacao":"Estimativa do total."},"detalhes":["2 drinks — 360 kcal","Azeitonas ou castanhas, porção pequena — 90 kcal"],"tags":["barzinho","combo"]},{"id":"drink-boa","titulo":"Margarita, Cosmopolitan ou caipiroska","descricao":"Duas doses, com tábua de queijos pequena.","nivel":"boa","energia":{"kcal":700,"mostrarKcal":true,"observacao":"Estimativa do total."},"detalhes":["2 drinks — 500 kcal","Tábua de queijos pequena — 200 kcal"],"tags":["barzinho","combo"]},{"id":"drink-ocasional","titulo":"Piña colada, sex on the beach ou caipirinha de frutas","descricao":"Duas doses, com três bruschettas.","nivel":"ocasional","energia":{"kcal":950,"mostrarKcal":true,"observacao":"Estimativa do total."},"detalhes":["2 drinks — 800 kcal","Bruschettas, 3 unidades — 150 kcal"],"tags":["barzinho","combo"]}]},{"id":"com-chopp","titulo":"Com chopp","pergunta":"Duas doses, mais o que vem para beliscar.","observacoes":[],"opcoes":[{"id":"chopp-melhor","titulo":"Dois chopps pequenos","descricao":"300 ml cada, com porção pequena de azeitonas ou castanhas.","nivel":"melhor","energia":{"kcal":330,"mostrarKcal":true,"observacao":"Estimativa do total."},"detalhes":["2 chopps de 300 ml — 240 kcal","Azeitonas ou castanhas, porção pequena — 90 kcal"],"tags":["barzinho","combo"]},{"id":"chopp-boa","titulo":"Dois chopps médios","descricao":"500 ml cada, com tábua de queijos pequena.","nivel":"boa","energia":{"kcal":600,"mostrarKcal":true,"observacao":"Estimativa do total."},"detalhes":["2 chopps de 500 ml — 400 kcal","Tábua de queijos pequena — 200 kcal"],"tags":["barzinho","combo"]},{"id":"chopp-ocasional","titulo":"Dois chopps grandes","descricao":"700 ml cada, com três bruschettas.","nivel":"ocasional","energia":{"kcal":710,"mostrarKcal":true,"observacao":"Estimativa do total."},"detalhes":["2 chopps de 700 ml — 560 kcal","Bruschettas, 3 unidades — 150 kcal"],"tags":["barzinho","combo"]}]}],"lembretes":[]}'::jsonb, array['barzinho', 'bar', 'drink', 'chopp', 'cerveja', 'happy hour', 'alcool', 'petisco']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('restaurantes', 'comer_fora', 'Restaurantes', null, null, 'restaurante', 8, 'rascunho', '{"introducao":null,"decisoes":[],"lembretes":[]}'::jsonb, array['restaurante', 'self service', 'buffet', 'por quilo']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('delivery', 'comer_fora', 'Delivery', null, null, 'delivery', 9, 'rascunho', '{"introducao":null,"decisoes":[],"lembretes":[]}'::jsonb, array['delivery', 'ifood', 'entrega']::text[]) on conflict (id) do nothing;

-- Guias -----------------------------------------------------------------------
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('rotulos', 'guia', 'Como ler um rótulo', 'Compras', 'A regra de ouro da lista de ingredientes.', null, 1, 'publicado', '{"secoes":[{"id":"regra-de-ouro","titulo":"Regra de ouro dos ingredientes","paragrafos":["Quanto menos ingredientes, melhor."],"itens":["Até 5 ingredientes: geralmente tudo certo.","De 6 a 10 ingredientes: vale olhar com atenção.","Lista longa e cheia de nomes estranhos: melhor evitar."]}]}'::jsonb, array['rotulo', 'ingredientes', 'industrializado', 'supermercado', 'embalagem']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('marcas-mercado', 'guia', 'Marcas sugeridas no mercado', 'Compras', 'O que procurar na prateleira, por categoria.', null, 2, 'publicado', '{"secoes":[{"id":"iogurte","titulo":"Iogurte","paragrafos":[],"itens":["Vigor Viv Simples e Vigor Viv Natural","Vigor Natural consistência firme","Nestlé Natural Desnatado e Nestlé Natural Integral (2 ingredientes)","Itambé Integral e Itambé Natural Milk","Fazenda Bela Vista Natural","Verde Campo LacFree","Verde Campo Natural Whey","Ati Latte natural","Batavo Naturais Integral","Yorgus Grego"]},{"id":"pao-de-forma","titulo":"Pão de forma","paragrafos":[],"itens":["Seven Boys Benefice e Benefice Light 7 Grãos","Seven Boys Integral, 12 Grãos e Castanha & Nozes","Wickbold 100% Integral (Girassol & Castanha, + Fibras, Pão Integral, Pão Forno)","Nutrella 14 Grãos, 7 Grãos e 100% Integral","Pullman Integral e Pullman 100% Integral 12 Grãos","Visconti Pão Integral"]},{"id":"geleia","titulo":"Geleia","paragrafos":[],"itens":["St. Dalfour (100% fruta)","Queensberry Wellness (100% fruta)","Casa Madeira frutas vermelhas, sem adição de açúcar","Ritter Geleia com Pedaços, 100% fruta"]},{"id":"frutas-congeladas","titulo":"Frutas congeladas","paragrafos":[],"itens":["Original Food"]},{"id":"vegetais-congelados","titulo":"Vegetais congelados","paragrafos":[],"itens":["De Marchi","Grano"]},{"id":"praticos","titulo":"Prontos que ajudam na correria","paragrafos":["Nas opções prontas, escolha sempre a de menos ingredientes."],"itens":["Frango desfiado congelado: Nat Pronto Já, peito de frango cozido desfiado","Lanche proteico: Verde Campo Natural Whey"]}]}'::jsonb, array['marcas', 'supermercado', 'iogurte', 'pao', 'geleia', 'congelados', 'compras']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('proteinas-em-casa', 'guia', 'Proteínas para ter em casa', 'Compras', 'Os cortes e itens que resolvem a semana.', null, 3, 'publicado', '{"secoes":[{"id":"lista","titulo":null,"paragrafos":[],"itens":["Tilápia","Atum","Peito de frango","Sobrecoxa de frango","Ovos","Filé mignon suíno","Camarão","Alcatra","Patinho","Peito de peru","Frango desfiado pronto — escolhendo sempre a opção com menos ingredientes"]}]}'::jsonb, array['proteina', 'carne', 'frango', 'peixe', 'ovo', 'compras']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('marmitas-comecar', 'guia', 'Marmitas: por onde começar', 'Marmitas', 'Higienizar, armazenar e deixar pronto para a semana.', null, 4, 'publicado', '{"secoes":[{"id":"higienizar","titulo":"Como higienizar frutas e legumes","paragrafos":["A higienização correta elimina bactérias, parasitas e resíduos.","Fruta organizada é fruta consumida: deixar já lavada, cortada e visível aumenta muito o consumo ao longo do dia."],"itens":["Lave em água corrente, esfregando fruta por fruta e legume por legume com as mãos.","Prepare a solução: 1 colher de sopa de água sanitária para 1 litro de água.","Deixe de molho por 15 minutos.","Enxágue novamente em água corrente.","Seque bem, ou deixe escorrer, antes de guardar.","Nunca misture água sanitária com vinagre."]},{"id":"mamao","titulo":"Mamão","paragrafos":["Dura até 3 dias na geladeira e 30 dias no congelador."],"itens":["Descasque, corte ao meio e retire as sementes.","Pique em cubos.","Armazene em pote fechado na geladeira."]},{"id":"morango","titulo":"Morango","paragrafos":["Lave apenas na hora de consumir. Dura até 3 dias na geladeira e 30 dias no congelador."],"itens":["Retire os morangos estragados.","Não lave antes de guardar.","Guarde os morangos secos em um pote com papel-toalha no fundo.","Tampe, mas sem vedar totalmente."]},{"id":"manga","titulo":"Manga","paragrafos":["Dura até 3 dias na geladeira e 30 dias no congelador."],"itens":["Descasque e pique.","Armazene em pote fechado."]},{"id":"abacaxi","titulo":"Abacaxi","paragrafos":["Dura até 3 dias na geladeira e 30 dias no congelador."],"itens":["Descasque e retire o miolo duro.","Corte em cubos ou rodelas.","Armazene em pote bem fechado."]},{"id":"basico","titulo":"O básico bem feito","paragrafos":["Não precisa inventar moda. Uma base bem feita, repetida ao longo da semana, gera constância e resultado."],"itens":[]}]}'::jsonb, array['marmita', 'higienizar', 'armazenar', 'fruta', 'legume', 'preparo', 'semana']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('marmitas-receitas', 'guia', 'Receitas para a semana', 'Marmitas', 'As bases que rendem várias marmitas.', null, 5, 'publicado', '{"secoes":[{"id":"frango-desfiado","titulo":"Frango desfiado bem temperado","paragrafos":["Fica soltinho, suculento e super versátil."],"itens":["1 kg de frango sassami","Tomate em bastante quantidade — quanto mais, mais molhadinho","1 cebola, alho a gosto","Sal, pimenta-do-reino, colorau, chimichurri e páprica defumada","Refogue o alho, a cebola e o tomate; acrescente o frango e tempere","Coloque água até um dedo antes de cobrir","Cozinhe na pressão: 20 minutos depois de pegar pressão","Abra, desfie e ajuste o sal"]},{"id":"sobrecoxa","titulo":"Sobrecoxa sem osso com cenoura","paragrafos":["Mesmo processo do frango sassami, trocando o sassami por sobrecoxa sem osso e acrescentando cenoura em rodelas. Carne mais palatável e muito saborosa."],"itens":[]},{"id":"pures","titulo":"Purês fáceis","paragrafos":[],"itens":["Batata: cozinhe, descarte a água (ajuda a reduzir o amido) e bata no liquidificador com leite desnatado, sal e um pouco de manteiga.","Mandioquinha: cozinhe por 20 a 25 minutos e bata no processador com sal e um pouco de manteiga.","Abóbora: cozinhe por 20 a 25 minutos e bata no processador com sal e um pouco de manteiga."]},{"id":"creme-de-milho","titulo":"Creme de milho fit","paragrafos":["Para colocar por cima do frango em cubos. Bata tudo e aqueça até engrossar."],"itens":["1 lata de milho","100 ml de leite desnatado","1 colher de creme de ricota light","Sal"]},{"id":"legumes","titulo":"Legumes rápidos e saborosos","paragrafos":[],"itens":["Cozinhe no vapor, ou","Refogue rapidamente, por 5 minutos, com alho, sal e um fio de azeite — só para pegar sabor, sem perder a textura."]},{"id":"estrogonofe","titulo":"Estrogonofe fit com batata palha crocante","paragrafos":["Quanto mais seca a batata antes de ir para a airfryer, mais crocante ela fica."],"itens":["Estrogonofe: frango em cubos, os temperos do frango sassami, creme de ricota light e um pouco de leite desnatado.","Batata palha: descasque e rale na lâmina julienne, a que deixa a batata bem fininha.","Deixe a batata ralada em água fria por 2 minutos para tirar o excesso de amido.","Escorra e seque muito bem, pode usar papel-toalha.","Tempere com sal e curry.","Airfryer por cerca de 15 minutos, mexendo durante o processo para dourar por igual."]},{"id":"frango-agridoce","titulo":"Frango agridoce simples","paragrafos":["Doce na medida certa, sem exageros."],"itens":["Frango","Alho","Um fio de mel","Páprica","Suco de laranja"]},{"id":"rap10","titulo":"Rap10 ou pão sírio recheado, para congelar","paragrafos":["Misture tudo cru, espalhe no rap10 ou no pão sírio, congele em saquinhos e leve direto à frigideira na hora de comer."],"itens":["Carne moída (patinho ou acém)","Cebola bem picada","Sal, azeite, páprica defumada","Cheiro-verde ou cebolinha"]},{"id":"shake","titulo":"Shake ou smoothie proteico","paragrafos":["É só bater tudo no liquidificador."],"itens":["150 g da fruta congelada da sua preferência","1 scoop de whey","Um pouco de água"]}]}'::jsonb, array['receita', 'frango', 'pure', 'estrogonofe', 'marmita', 'airfryer', 'batata palha']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('sem-tempo', 'guia', 'Sem tempo: o que fazer', 'Marmitas', 'Atalhos que mantêm a alimentação de pé numa semana corrida.', null, 6, 'publicado', '{"secoes":[{"id":"congelados","titulo":"Congelados que resolvem","paragrafos":["Nas opções prontas, escolha sempre a de menos ingredientes."],"itens":["Vegetais congelados: De Marchi, Grano","Frutas congeladas: Original Food","Frango desfiado congelado: Nat Pronto Já","Lanche proteico: Verde Campo Natural Whey"]},{"id":"links","titulo":"Links úteis","paragrafos":["Potes e sacos de plástico também são fáceis de achar em atacados como Atacadão, Assaí e Mineirão."],"itens":["Saco hermético para armazenar comida, dá para reutilizar 3 ou 4 vezes: https://br.shp.ee/UhjNXte","Saco mais barato, sem zip lock — tem que dar um nó: https://br.shp.ee/xZNjQNe","Potes herméticos: https://a.co/d/04xz4d14","Balança: https://br.shp.ee/eva5PxT","Potes de vidro para marmita, 600 ml: https://br.shp.ee/dNXK3vQ","Potes de plástico: https://br.shp.ee/powmiJJ"]}]}'::jsonb, array['sem tempo', 'correria', 'congelado', 'pratico', 'atalho', 'potes', 'balanca']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('variar-em-casa', 'guia', 'Variar em casa', 'Marmitas', 'Ideias para fugir da repetição sem sair do plano.', null, 7, 'rascunho', '{"secoes":[]}'::jsonb, array['variar', 'sexta', 'ideias', 'receita', 'rotina']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('refeicao-livre', 'guia', 'Refeição livre', 'No dia a dia', 'Como ela se encaixa, e o que vem depois.', null, 8, 'publicado', '{"secoes":[{"id":"por-que","titulo":"Por que ela existe","paragrafos":["Incluir uma refeição livre na rotina pode ser uma maneira de fortalecer sua relação com a alimentação, trazendo mais flexibilidade e prazer ao processo.","Isso não significa exagerar nem perder o foco nos seus objetivos: trata-se de encontrar equilíbrio, respeitando seu corpo e suas escolhas.","Comida é muito mais do que nutrientes. Ela também carrega memórias, afetos e momentos especiais. Saborear algo que você gosta, num encontro com amigos ou num momento de autocuidado, também faz parte de uma vida saudável."],"itens":[]},{"id":"como-contar","titulo":"Como contar","paragrafos":["As opções da área Comer fora já vêm marcadas como completas ou meias."],"itens":["Duas meias refeições equivalem a uma refeição completa.","Uma completa mais uma meia equivalem a uma refeição e meia."]},{"id":"depois","titulo":"Depois da refeição livre","paragrafos":["Depois de aproveitar sua refeição livre, o mais importante é simplesmente seguir em frente. Volte com naturalidade para o seu plano alimentar, mantendo o foco na constância.","Uma alimentação equilibrada é feita de escolhas conscientes ao longo do tempo, e uma refeição fora da rotina não anula todo o seu progresso."],"itens":[]}]}'::jsonb, array['refeicao livre', 'flexibilidade', 'equilibrio']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('comer-fora', 'guia', 'Comer fora', 'No dia a dia', null, null, 9, 'rascunho', '{"secoes":[]}'::jsonb, array['comer fora', 'restaurante']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('industrializados', 'guia', 'Industrializados', 'No dia a dia', null, null, 10, 'rascunho', '{"secoes":[]}'::jsonb, array['industrializado', 'ultraprocessado']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('doces', 'guia', 'Doces', 'No dia a dia', null, null, 11, 'rascunho', '{"secoes":[]}'::jsonb, array['doce', 'sobremesa', 'acucar']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('alcool', 'guia', 'Álcool', 'No dia a dia', null, null, 12, 'rascunho', '{"secoes":[]}'::jsonb, array['alcool', 'bebida', 'cerveja', 'vinho']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('constipacao', 'guia', 'Constipação', 'Digestão', null, null, 13, 'rascunho', '{"secoes":[]}'::jsonb, array['constipacao', 'intestino preso', 'fibra']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('gases', 'guia', 'Gases', 'Digestão', null, null, 14, 'rascunho', '{"secoes":[]}'::jsonb, array['gases', 'flatulencia']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('distensao-abdominal', 'guia', 'Distensão abdominal', 'Digestão', null, null, 15, 'rascunho', '{"secoes":[]}'::jsonb, array['distensao', 'inchaco', 'barriga']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('diarreia', 'guia', 'Diarreia', 'Digestão', null, null, 16, 'rascunho', '{"secoes":[]}'::jsonb, array['diarreia', 'intestino solto']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('lactose', 'guia', 'Lactose', 'Restrições', null, null, 17, 'rascunho', '{"secoes":[]}'::jsonb, array['lactose', 'leite', 'laticinio']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('fodmap', 'guia', 'FODMAP', 'Restrições', null, null, 18, 'rascunho', '{"secoes":[]}'::jsonb, array['fodmap', 'sii', 'intestino irritavel']::text[]) on conflict (id) do nothing;

-- Configurações ---------------------------------------------------------------
insert into configuracoes (chave, valor, descricao) values ('nome_central', '"Central do Paciente"'::jsonb, 'Nome exibido no topo do app.') on conflict (chave) do nothing;
insert into configuracoes (chave, valor, descricao) values ('frase_home', '"Facilite suas escolhas no dia a dia."'::jsonb, 'Frase da tela inicial.') on conflict (chave) do nothing;
insert into configuracoes (chave, valor, descricao) values ('lema', '"Na sexta, o cardápio muda. O plano continua."'::jsonb, 'Frase curta de identidade, exibida na tela inicial. Deixe em branco para não mostrar.') on conflict (chave) do nothing;
insert into configuracoes (chave, valor, descricao) values ('comer_fora_introducao', '"Duas meias refeições equivalem a uma completa. Uma completa mais uma meia equivalem a uma refeição e meia."'::jsonb, 'Frase no topo de Comer fora. Deixe em branco para não mostrar.') on conflict (chave) do nothing;
insert into configuracoes (chave, valor, descricao) values ('whatsapp', '"5531994503318"'::jsonb, 'Número do WhatsApp da nutricionista, só dígitos com DDI e DDD (ex.: 5511999999999).') on conflict (chave) do nothing;
insert into configuracoes (chave, valor, descricao) values ('nome_nutricionista', '"Isabela Marçal"'::jsonb, 'Nome que aparece nos textos de contato.') on conflict (chave) do nothing;
insert into configuracoes (chave, valor, descricao) values ('alerta_vencimento_dias', '15'::jsonb, 'A partir de quantos dias antes do fim o paciente entra em ''próximo do vencimento''.') on conflict (chave) do nothing;


-- ###########################################################################
-- 0005_permissoes.sql
-- ###########################################################################

-- =============================================================================
-- CENTRAL DO PACIENTE — 0005: permissões de tabela
--
-- O Supabase já concede isto por padrão às contas anônima e autenticada; a
-- declaração explícita existe para que as migrações rodem iguais em qualquer
-- Postgres (é assim que a bateria de testes de acesso é executada antes do
-- deploy) e para deixar por escrito quem alcança o quê.
--
-- Conceder acesso à tabela NÃO é conceder acesso à linha: quem filtra linha
-- é a política de 0003. Sem política, a tabela com RLS ligado não devolve
-- nada, nem para quem tem GRANT.
-- =============================================================================

grant usage on schema public to anon, authenticated;

grant select on
  planos, unidades, grupos_alimentares, alimentos, equivalencias,
  conteudos, configuracoes, perfis, pacientes, pacientes_visao
to authenticated;

grant select, insert, delete on favoritos to authenticated;

-- A nutricionista usa a mesma conta autenticada de todo mundo: o que a
-- separa é `e_admin()` dentro das políticas, não um papel de banco diferente.
grant insert, update, delete on
  pacientes, planos, perfis, convites, historico_admin,
  unidades, grupos_alimentares, alimentos, equivalencias, conteudos, configuracoes
to authenticated;

grant select on historico_admin, convites to authenticated;

grant usage, select on all sequences in schema public to authenticated;
