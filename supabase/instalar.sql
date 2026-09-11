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
create or replace function vincular_paciente_ao_perfil()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_perfil uuid;
begin
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
insert into grupos_alimentares (id, nome, descricao, ordem, regra, troca_por_porcao, tags) values ('carboidratos', 'Carboidratos', 'Arroz, massas, tubérculos, pães e raízes.', 1, '{"tipo":"porcoes"}'::jsonb, true, array['carboidrato', 'massa', 'arroz', 'pao', 'tuberculo']::text[]) on conflict (id) do nothing;
insert into grupos_alimentares (id, nome, descricao, ordem, regra, troca_por_porcao, tags) values ('proteinas', 'Proteínas', 'Carnes, ovos, peixes e outras fontes proteicas.', 2, '{"tipo":"porcoes"}'::jsonb, true, array['proteina', 'carne', 'ovo', 'peixe', 'frango']::text[]) on conflict (id) do nothing;
insert into grupos_alimentares (id, nome, descricao, ordem, regra, troca_por_porcao, tags) values ('gorduras', 'Gorduras', 'Azeites, oleaginosas, abacate e similares.', 3, '{"tipo":"porcoes"}'::jsonb, true, array['gordura', 'azeite', 'castanha', 'abacate']::text[]) on conflict (id) do nothing;
insert into grupos_alimentares (id, nome, descricao, ordem, regra, troca_por_porcao, tags) values ('frutas', 'Frutas', 'Frutas in natura e suas porções.', 4, '{"tipo":"porcoes"}'::jsonb, true, array['fruta']::text[]) on conflict (id) do nothing;
insert into grupos_alimentares (id, nome, descricao, ordem, regra, troca_por_porcao, tags) values ('vegetais-livres', 'Vegetais livres', 'Quantidade livre, respeitando a porção mínima das refeições principais.', 5, '{"tipo":"livre","minimos":[{"refeicao":"Almoço","medida":{"quantidade":150,"unidadeId":"g"}},{"refeicao":"Jantar","medida":{"quantidade":150,"unidadeId":"g"}}],"texto":"Quantidade livre. No almoço e no jantar, a porção mínima é de 150 g."}'::jsonb, false, array['vegetal', 'legume', 'verdura', 'salada', 'livre']::text[]) on conflict (id) do nothing;
insert into grupos_alimentares (id, nome, descricao, ordem, regra, troca_por_porcao, tags) values ('outros', 'Outros', 'Itens que não se encaixam nos grupos acima.', 6, null, false, array['outros']::text[]) on conflict (id) do nothing;

-- Alimentos -------------------------------------------------------------------
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('arroz-cozido', 'Arroz integral ou branco cozido', 'carboidratos', 'g', 100, 'g', '[]'::jsonb, true, true, array['arroz', 'integral', 'branco', 'cozido']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('macarrao-cozido', 'Macarrão cozido', 'carboidratos', 'g', 80, 'g', '[]'::jsonb, false, true, array['macarrao', 'massa', 'espaguete', 'penne']::text[], 'Porção derivada da equivalência 100 g de arroz = 80 g de macarrão.') on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('abobora-cozida', 'Abóbora cozida', 'carboidratos', 'g', null, null, '[]'::jsonb, true, true, array['abobora', 'jerimum']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('batata-cozida', 'Batata cozida', 'carboidratos', 'g', null, null, '[]'::jsonb, true, true, array['batata', 'tuberculo']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('pao', 'Pão', 'carboidratos', 'g', null, null, '[]'::jsonb, null, null, array['pao', 'frances', 'forma']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('tapioca', 'Tapioca', 'carboidratos', 'g', null, null, '[]'::jsonb, true, true, array['tapioca', 'goma']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('abobrinha', 'Abobrinha', 'vegetais-livres', 'g', null, null, '[]'::jsonb, true, true, array['vegetal', 'legume', 'livre']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('aspargos', 'Aspargos', 'vegetais-livres', 'g', null, null, '[]'::jsonb, true, true, array['vegetal', 'legume', 'livre']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('alho', 'Alho', 'vegetais-livres', 'g', null, null, '[]'::jsonb, true, true, array['vegetal', 'legume', 'livre']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('alho-poro', 'Alho-poró', 'vegetais-livres', 'g', null, null, '[]'::jsonb, true, true, array['vegetal', 'legume', 'livre']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('berinjela', 'Berinjela', 'vegetais-livres', 'g', null, null, '[]'::jsonb, true, true, array['vegetal', 'legume', 'livre']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('beterraba', 'Beterraba', 'vegetais-livres', 'g', null, null, '[]'::jsonb, true, true, array['vegetal', 'legume', 'livre']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('brocolis', 'Brócolis', 'vegetais-livres', 'g', null, null, '[]'::jsonb, true, true, array['vegetal', 'legume', 'livre']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('cebola', 'Cebola', 'vegetais-livres', 'g', null, null, '[]'::jsonb, true, true, array['vegetal', 'legume', 'livre']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('cenoura', 'Cenoura', 'vegetais-livres', 'g', null, null, '[]'::jsonb, true, true, array['vegetal', 'legume', 'livre']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('chuchu', 'Chuchu', 'vegetais-livres', 'g', null, null, '[]'::jsonb, true, true, array['vegetal', 'legume', 'livre']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('cogumelos', 'Cogumelos', 'vegetais-livres', 'g', null, null, '[]'::jsonb, true, true, array['vegetal', 'legume', 'livre']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('couve-flor', 'Couve-flor', 'vegetais-livres', 'g', null, null, '[]'::jsonb, true, true, array['vegetal', 'legume', 'livre']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('couve-de-bruxelas', 'Couve-de-bruxelas', 'vegetais-livres', 'g', null, null, '[]'::jsonb, true, true, array['vegetal', 'legume', 'livre']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('ervilha-torta', 'Ervilha-torta', 'vegetais-livres', 'g', null, null, '[]'::jsonb, true, true, array['vegetal', 'legume', 'livre']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('jilo', 'Jiló', 'vegetais-livres', 'g', null, null, '[]'::jsonb, true, true, array['vegetal', 'legume', 'livre']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('maxixe', 'Maxixe', 'vegetais-livres', 'g', null, null, '[]'::jsonb, true, true, array['vegetal', 'legume', 'livre']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('nabo', 'Nabo', 'vegetais-livres', 'g', null, null, '[]'::jsonb, true, true, array['vegetal', 'legume', 'livre']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('palmito', 'Palmito', 'vegetais-livres', 'g', null, null, '[]'::jsonb, true, true, array['vegetal', 'legume', 'livre']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('pimentao', 'Pimentão', 'vegetais-livres', 'g', null, null, '[]'::jsonb, true, true, array['vegetal', 'legume', 'livre']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('pepino', 'Pepino', 'vegetais-livres', 'g', null, null, '[]'::jsonb, true, true, array['vegetal', 'legume', 'livre']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('repolho', 'Repolho', 'vegetais-livres', 'g', null, null, '[]'::jsonb, true, true, array['vegetal', 'legume', 'livre']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('quiabo', 'Quiabo', 'vegetais-livres', 'g', null, null, '[]'::jsonb, true, true, array['vegetal', 'legume', 'livre']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('rabanete', 'Rabanete', 'vegetais-livres', 'g', null, null, '[]'::jsonb, true, true, array['vegetal', 'legume', 'livre']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('tomate', 'Tomate', 'vegetais-livres', 'g', null, null, '[]'::jsonb, true, true, array['vegetal', 'legume', 'livre']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('tomatinho', 'Tomatinho', 'vegetais-livres', 'g', null, null, '[]'::jsonb, true, true, array['vegetal', 'legume', 'livre']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('vagem', 'Vagem', 'vegetais-livres', 'g', null, null, '[]'::jsonb, true, true, array['vegetal', 'legume', 'livre']::text[], null) on conflict (id) do nothing;
insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values ('folhas-e-brotos', 'Folhas e brotos', 'vegetais-livres', 'g', null, null, '[]'::jsonb, true, true, array['vegetal', 'legume', 'livre']::text[], null) on conflict (id) do nothing;

-- Equivalências ---------------------------------------------------------------
insert into equivalencias (id, origem_alimento_id, destino_alimento_id, tipo, regra, bidirecional, fonte, observacao) values ('arroz-para-macarrao', 'arroz-cozido', 'macarrao-cozido', 'proporcional', '{"tipo":"proporcional","de":{"quantidade":100,"unidadeId":"g"},"para":{"quantidade":80,"unidadeId":"g"}}'::jsonb, true, 'Lista de substituição', null) on conflict (id) do nothing;

-- Comer fora ------------------------------------------------------------------
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('hamburguer', 'comer_fora', 'Hambúrguer', null, 'Como montar o lanche do jeito que cabe no seu dia.', 'hamburguer', 1, 'publicado', '{"introducao":"Compare as montagens antes de pedir. A diferença costuma estar no número de camadas, não no lanche em si.","decisoes":[{"id":"montagem","titulo":"A montagem do lanche","pergunta":"Quantas camadas o lanche tem?","opcoes":[{"id":"hamburguer-simples","titulo":"Montagem mais simples","descricao":null,"nivel":"melhor","energia":null,"detalhes":[],"tags":["hamburguer","simples"]},{"id":"hamburguer-denso","titulo":"Combinações mais densas em energia","descricao":null,"nivel":"ocasional","energia":null,"detalhes":[],"tags":["hamburguer","duplo","bacon","cheddar"]}]}],"lembretes":[]}'::jsonb, array['hamburguer', 'lanche', 'burger']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('japonesa', 'comer_fora', 'Comida japonesa', null, 'Entradas, pratos e o que costuma pesar no rodízio.', 'japonesa', 2, 'publicado', '{"introducao":"Comece pelas entradas, escolha o prato principal e deixe as preparações fritas e os molhos cremosos como parte menor da refeição.","decisoes":[{"id":"entradas","titulo":"Entradas","pergunta":"Por onde começar?","opcoes":[{"id":"sunomono","titulo":"Sunomono","descricao":null,"nivel":"melhor","energia":null,"detalhes":[],"tags":["sunomono","pepino"]},{"id":"missoshiro","titulo":"Missoshiro","descricao":null,"nivel":"melhor","energia":null,"detalhes":[],"tags":["missoshiro","sopa","miso"]},{"id":"edamame","titulo":"Edamame","descricao":null,"nivel":"melhor","energia":null,"detalhes":[],"tags":["edamame","soja"]}]},{"id":"principal","titulo":"O prato principal","pergunta":"O que pedir depois das entradas?","opcoes":[{"id":"sashimi","titulo":"Sashimi","descricao":null,"nivel":"melhor","energia":null,"detalhes":[],"tags":["sashimi","peixe"]},{"id":"niguiri","titulo":"Niguiri","descricao":null,"nivel":"boa","energia":null,"detalhes":[],"tags":["niguiri","sushi"]}]},{"id":"ocasionais","titulo":"Preparações fritas e molhos cremosos","pergunta":"E os itens que aparecem no rodízio?","opcoes":[{"id":"fritos","titulo":"Preparações fritas","descricao":null,"nivel":"ocasional","energia":null,"detalhes":[],"tags":["frito","tempura","hot"]},{"id":"molhos-cremosos","titulo":"Molhos cremosos","descricao":null,"nivel":"ocasional","energia":null,"detalhes":[],"tags":["molho","cremoso"]}]}],"lembretes":[]}'::jsonb, array['japonesa', 'japones', 'sushi', 'sashimi', 'rodizio', 'temaki']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('massas', 'comer_fora', 'Massas', null, 'Quantidade da massa, proteína e molho.', 'massas', 3, 'publicado', '{"introducao":"Três escolhas definem o prato: quanto de massa, se entra proteína e qual molho acompanha.","decisoes":[{"id":"quantidade","titulo":"Quantidade da massa","pergunta":"Quanto de massa vem no prato?","opcoes":[]},{"id":"proteina","titulo":"A proteína","pergunta":"O prato inclui proteína?","opcoes":[]},{"id":"molho","titulo":"O molho","pergunta":"Qual molho acompanha?","opcoes":[]}],"lembretes":[]}'::jsonb, array['massa', 'macarrao', 'italiano', 'molho']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('doces', 'comer_fora', 'Doces e sobremesas', null, 'Tipos de sobremesa e o tamanho da porção.', 'doces', 4, 'publicado', '{"introducao":"A escolha da sobremesa e o tamanho da porção contam juntos.","decisoes":[{"id":"tipo","titulo":"O tipo de sobremesa","pergunta":"Qual sobremesa está na mesa?","opcoes":[]},{"id":"porcao","titulo":"A porção","pergunta":"Quanto vem servido?","opcoes":[]}],"lembretes":[]}'::jsonb, array['doce', 'sobremesa', 'chocolate', 'bolo']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('subway', 'comer_fora', 'Subway', null, null, 'sanduiche', 5, 'rascunho', '{"introducao":null,"decisoes":[],"lembretes":[]}'::jsonb, array['subway', 'sanduiche', 'sub']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('pizza', 'comer_fora', 'Pizza', null, null, 'pizza', 6, 'rascunho', '{"introducao":null,"decisoes":[],"lembretes":[]}'::jsonb, array['pizza', 'pizzaria']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('acai', 'comer_fora', 'Açaí', null, null, 'acai', 7, 'rascunho', '{"introducao":null,"decisoes":[],"lembretes":[]}'::jsonb, array['acai', 'tigela']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('restaurantes', 'comer_fora', 'Restaurantes', null, null, 'restaurante', 8, 'rascunho', '{"introducao":null,"decisoes":[],"lembretes":[]}'::jsonb, array['restaurante', 'self service', 'buffet', 'por quilo']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('delivery', 'comer_fora', 'Delivery', null, null, 'delivery', 9, 'rascunho', '{"introducao":null,"decisoes":[],"lembretes":[]}'::jsonb, array['delivery', 'ifood', 'entrega']::text[]) on conflict (id) do nothing;

-- Guias -----------------------------------------------------------------------
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('refeicao-livre', 'guia', 'Refeição livre', 'No dia a dia', null, null, 1, 'rascunho', '{"secoes":[]}'::jsonb, array['refeicao livre', 'flexibilidade']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('comer-fora', 'guia', 'Comer fora', 'No dia a dia', null, null, 2, 'rascunho', '{"secoes":[]}'::jsonb, array['comer fora', 'restaurante']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('industrializados', 'guia', 'Industrializados', 'No dia a dia', null, null, 3, 'rascunho', '{"secoes":[]}'::jsonb, array['industrializado', 'rotulo', 'ultraprocessado']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('doces', 'guia', 'Doces', 'No dia a dia', null, null, 4, 'rascunho', '{"secoes":[]}'::jsonb, array['doce', 'sobremesa', 'acucar']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('alcool', 'guia', 'Álcool', 'No dia a dia', null, null, 5, 'rascunho', '{"secoes":[]}'::jsonb, array['alcool', 'bebida', 'cerveja', 'vinho']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('constipacao', 'guia', 'Constipação', 'Digestão', null, null, 6, 'rascunho', '{"secoes":[]}'::jsonb, array['constipacao', 'intestino preso', 'fibra']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('gases', 'guia', 'Gases', 'Digestão', null, null, 7, 'rascunho', '{"secoes":[]}'::jsonb, array['gases', 'flatulencia']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('distensao-abdominal', 'guia', 'Distensão abdominal', 'Digestão', null, null, 8, 'rascunho', '{"secoes":[]}'::jsonb, array['distensao', 'inchaco', 'barriga']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('diarreia', 'guia', 'Diarreia', 'Digestão', null, null, 9, 'rascunho', '{"secoes":[]}'::jsonb, array['diarreia', 'intestino solto']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('lactose', 'guia', 'Lactose', 'Restrições', null, null, 10, 'rascunho', '{"secoes":[]}'::jsonb, array['lactose', 'leite', 'laticinio']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('fodmap', 'guia', 'FODMAP', 'Restrições', null, null, 11, 'rascunho', '{"secoes":[]}'::jsonb, array['fodmap', 'sii', 'intestino irritavel']::text[]) on conflict (id) do nothing;

-- Configurações ---------------------------------------------------------------
insert into configuracoes (chave, valor, descricao) values ('nome_central', '"Central do Paciente"'::jsonb, 'Nome exibido no topo do app.') on conflict (chave) do nothing;
insert into configuracoes (chave, valor, descricao) values ('frase_home', '"Facilite suas escolhas no dia a dia."'::jsonb, 'Frase da tela inicial.') on conflict (chave) do nothing;
insert into configuracoes (chave, valor, descricao) values ('whatsapp', '""'::jsonb, 'Número do WhatsApp da nutricionista, só dígitos com DDI e DDD (ex.: 5511999999999).') on conflict (chave) do nothing;
insert into configuracoes (chave, valor, descricao) values ('nome_nutricionista', '""'::jsonb, 'Nome que aparece nos textos de contato.') on conflict (chave) do nothing;
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
