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
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('refeicao-livre', 'comer_fora', 'Refeição livre', null, 'Como contar uma refeição completa e uma meia refeição.', 'taca', 1, 'publicado', '{"introducao":"Duas meias refeições equivalem a uma completa. Uma completa mais uma meia equivalem a uma refeição e meia. É com essa conta que as opções abaixo se encaixam na sua semana.","decisoes":[{"id":"completas","titulo":"Refeições completas","pergunta":"Cada uma destas fecha uma refeição livre inteira.","observacoes":[],"opcoes":[{"id":"completa-hamburguer","titulo":"Hambúrguer com batata frita pequena e refrigerante zero açúcar","descricao":null,"nivel":null,"energia":null,"detalhes":[],"tags":["hamburguer","lanche","batata"]},{"id":"completa-pizza","titulo":"Pizza","descricao":"3 fatias de massa fina, ou 2 fatias de massa grossa ou de borda recheada.","nivel":null,"energia":null,"detalhes":["Prefira opções com proteína e sem muita adição de queijo, como frango ou carne seca."],"tags":["pizza"]},{"id":"completa-acai","titulo":"Açaí de 500 ml com banana e leite condensado","descricao":null,"nivel":null,"energia":null,"detalhes":[],"tags":["acai","banana"]}]},{"id":"meias","titulo":"Meias refeições","pergunta":"Duas delas somam uma refeição completa.","observacoes":[],"opcoes":[{"id":"meia-acai","titulo":"Açaí de 300 ml com 1 fruta e leite condensado","descricao":null,"nivel":null,"energia":null,"detalhes":[],"tags":["acai"]},{"id":"meia-gelato","titulo":"Gelato: 1 copo médio com 2 sabores","descricao":"Bacio di Latte, Lullo, Mi Garba.","nivel":null,"energia":null,"detalhes":[],"tags":["gelato","sorvete"]},{"id":"meia-cookie","titulo":"1 cookie artesanal grande, estilo americano","descricao":"Mr. Cheney, American Day.","nivel":null,"energia":null,"detalhes":[],"tags":["cookie","biscoito"]},{"id":"meia-bolo","titulo":"1 fatia média de bolo ou torta com calda","descricao":null,"nivel":null,"energia":null,"detalhes":[],"tags":["bolo","torta"]},{"id":"meia-temaki","titulo":"1 temaki simples, sem cream cheese","descricao":null,"nivel":null,"energia":null,"detalhes":[],"tags":["temaki","japonesa"]},{"id":"meia-brownie","titulo":"1 brownie com 1 bola de sorvete","descricao":null,"nivel":null,"energia":null,"detalhes":[],"tags":["brownie","sorvete"]},{"id":"meia-milkshake","titulo":"Milkshake pequeno","descricao":"Bob''s, McDonald''s.","nivel":null,"energia":{"kcal":330,"mostrarKcal":false,"observacao":null},"detalhes":[],"tags":["milkshake"]}]},{"id":"bebidas","titulo":"Bebidas","pergunta":"Equivalências de bebida alcoólica.","observacoes":[],"opcoes":[{"id":"bebida-vinho","titulo":"2 taças de vinho","descricao":null,"nivel":null,"energia":null,"detalhes":[],"tags":["vinho","alcool"]},{"id":"bebida-longneck","titulo":"2 long necks","descricao":null,"nivel":null,"energia":null,"detalhes":[],"tags":["cerveja","alcool"]},{"id":"bebida-drinks","titulo":"2 drinks","descricao":null,"nivel":null,"energia":null,"detalhes":[],"tags":["drink","alcool"]},{"id":"bebida-aperol","titulo":"2 aperol","descricao":null,"nivel":null,"energia":null,"detalhes":[],"tags":["aperol","alcool"]}]}],"lembretes":["Depois de aproveitar a refeição livre, o mais importante é seguir em frente e voltar com naturalidade ao seu plano.","Uma alimentação equilibrada é feita de escolhas conscientes ao longo do tempo — uma refeição fora da rotina não anula o seu progresso."]}'::jsonb, array['refeicao livre', 'livre', 'meia refeicao', 'sobremesa', 'bebida']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('hamburguer', 'comer_fora', 'Hambúrguer', null, 'Como montar o lanche do jeito que cabe no seu dia.', 'hamburguer', 2, 'publicado', '{"introducao":"Compare as montagens antes de pedir. A diferença costuma estar no número de camadas, não no lanche em si.","decisoes":[{"id":"montagem","titulo":"A montagem do lanche","pergunta":"Quantas camadas o lanche tem?","observacoes":[],"opcoes":[{"id":"hamburguer-simples","titulo":"Montagem mais simples","descricao":null,"nivel":"melhor","energia":null,"detalhes":[],"tags":["simples"]},{"id":"hamburguer-denso","titulo":"Combinações mais densas em energia","descricao":null,"nivel":"ocasional","energia":null,"detalhes":[],"tags":["duplo","bacon","cheddar"]}]},{"id":"completa","titulo":"Como refeição livre completa","pergunta":null,"observacoes":[],"opcoes":[{"id":"hamburguer-completa","titulo":"Hambúrguer, batata frita pequena e refrigerante zero açúcar","descricao":null,"nivel":null,"energia":null,"detalhes":[],"tags":["refeicao livre"]}]}],"lembretes":[]}'::jsonb, array['hamburguer', 'lanche', 'burger']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('japonesa', 'comer_fora', 'Comida japonesa', null, 'Entradas, combinados e o que costuma pesar no rodízio.', 'japonesa', 3, 'publicado', '{"introducao":"Comece pelas entradas, escolha o combinado e deixe as preparações fritas e os molhos cremosos como parte menor da refeição.","decisoes":[{"id":"entradas","titulo":"Entradas","pergunta":"Por onde começar?","observacoes":[],"opcoes":[{"id":"sunomono","titulo":"Sunomono","descricao":null,"nivel":"melhor","energia":null,"detalhes":[],"tags":["sunomono","pepino"]},{"id":"missoshiro","titulo":"Missoshiro","descricao":null,"nivel":"melhor","energia":null,"detalhes":[],"tags":["missoshiro","sopa","miso"]},{"id":"edamame","titulo":"Edamame","descricao":null,"nivel":"melhor","energia":null,"detalhes":[],"tags":["edamame","soja"]}]},{"id":"principal","titulo":"Combinados","pergunta":"O que pedir depois das entradas?","observacoes":["Sugestão de 20 peças.","Peças simples, sem molho.","Molho shoyu tradicional ou light.","O salmão é um peixe muito saudável, mas é rico em gordura, o que eleva o valor calórico da refeição. Para reduzir, prefira atum, peixe branco ou camarão."],"opcoes":[{"id":"sashimi","titulo":"Sashimi","descricao":null,"nivel":"melhor","energia":null,"detalhes":[],"tags":["sashimi","peixe"]},{"id":"niguiri","titulo":"Niguiri","descricao":null,"nivel":"boa","energia":null,"detalhes":[],"tags":["niguiri","sushi"]},{"id":"temaki-simples","titulo":"Temaki simples, sem cream cheese","descricao":"Conta como meia refeição livre.","nivel":"boa","energia":null,"detalhes":[],"tags":["temaki"]}]},{"id":"ocasionais","titulo":"Preparações fritas e molhos cremosos","pergunta":"E os itens que aparecem no rodízio?","observacoes":[],"opcoes":[{"id":"fritos","titulo":"Preparações fritas","descricao":null,"nivel":"ocasional","energia":null,"detalhes":[],"tags":["frito","tempura","hot"]},{"id":"molhos-cremosos","titulo":"Molhos cremosos","descricao":null,"nivel":"ocasional","energia":null,"detalhes":[],"tags":["molho","cremoso"]}]}],"lembretes":[]}'::jsonb, array['japonesa', 'japones', 'sushi', 'sashimi', 'rodizio', 'temaki']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('massas', 'comer_fora', 'Massas', null, 'Quantidade da massa, proteína e molho.', 'massas', 4, 'publicado', '{"introducao":"Três escolhas definem o prato: quanto de massa, se entra proteína e qual molho acompanha.","decisoes":[{"id":"montagens","titulo":"Montagens que fecham uma refeição completa","pergunta":"Qual delas combina com o lugar onde você está?","observacoes":["Prefira o molho ao sugo.","Adicione proteína para trazer mais saciedade: massa e frango, massa e camarão, massa e carne magra.","Boa opção de restaurante: Spoleto."],"opcoes":[{"id":"massa-camarao","titulo":"Massa (200 g) com camarão (120 g), ricota temperada e molho pesto","descricao":null,"nivel":null,"energia":null,"detalhes":[],"tags":["camarao","pesto","ricota"]},{"id":"massa-frango","titulo":"Massa (100 g) com frango, legumes e molho pomodoro","descricao":null,"nivel":null,"energia":null,"detalhes":[],"tags":["frango","pomodoro","legumes"]},{"id":"massa-lasanha","titulo":"Lasanha bolonhesa","descricao":null,"nivel":null,"energia":null,"detalhes":[],"tags":["lasanha","bolonhesa"]}]}],"lembretes":[]}'::jsonb, array['massa', 'macarrao', 'italiano', 'molho', 'spoleto', 'lasanha']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('pizza', 'comer_fora', 'Pizza', null, 'Quantas fatias fecham uma refeição, por tipo de massa.', 'pizza', 5, 'publicado', '{"introducao":"A conta muda com a massa: quanto mais densa, menos fatias fecham a mesma refeição.","decisoes":[{"id":"fatias","titulo":"Quantas fatias","pergunta":"Qual é a massa da pizzaria?","observacoes":["Prefira opções com proteína e sem muita adição de queijo, como frango ou carne seca."],"opcoes":[{"id":"pizza-fina","titulo":"3 fatias de massa fina","descricao":null,"nivel":null,"energia":null,"detalhes":[],"tags":["massa fina"]},{"id":"pizza-grossa","titulo":"2 fatias de massa grossa ou de borda recheada","descricao":null,"nivel":null,"energia":null,"detalhes":[],"tags":["massa grossa","borda recheada"]}]}],"lembretes":[]}'::jsonb, array['pizza', 'pizzaria', 'fatia', 'borda']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('acai', 'comer_fora', 'Açaí', null, 'Tamanho da tigela e o que entra junto.', 'acai', 6, 'publicado', '{"introducao":"O tamanho decide se o açaí é a refeição livre inteira ou metade dela.","decisoes":[{"id":"tamanho","titulo":"O tamanho da tigela","pergunta":"Quanto vem no copo?","observacoes":[],"opcoes":[{"id":"acai-500","titulo":"500 ml com banana e leite condensado","descricao":"Fecha uma refeição livre completa.","nivel":null,"energia":null,"detalhes":[],"tags":["completa"]},{"id":"acai-300","titulo":"300 ml com 1 fruta e leite condensado","descricao":"Conta como meia refeição livre.","nivel":null,"energia":null,"detalhes":[],"tags":["meia"]}]}],"lembretes":[]}'::jsonb, array['acai', 'tigela', 'copo']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('doces', 'comer_fora', 'Doces e sobremesas', null, 'Cada uma destas conta como meia refeição livre.', 'doces', 7, 'publicado', '{"introducao":"Duas destas opções somam uma refeição livre completa.","decisoes":[{"id":"sobremesas","titulo":"Meias refeições doces","pergunta":"O que está na mesa?","observacoes":[],"opcoes":[{"id":"doce-gelato","titulo":"Gelato: 1 copo médio com 2 sabores","descricao":"Bacio di Latte, Lullo, Mi Garba.","nivel":null,"energia":null,"detalhes":[],"tags":["gelato","sorvete"]},{"id":"doce-cookie","titulo":"1 cookie artesanal grande, estilo americano","descricao":"Mr. Cheney, American Day.","nivel":null,"energia":null,"detalhes":[],"tags":["cookie"]},{"id":"doce-bolo","titulo":"1 fatia média de bolo ou torta com calda","descricao":null,"nivel":null,"energia":null,"detalhes":[],"tags":["bolo","torta"]},{"id":"doce-brownie","titulo":"1 brownie com 1 bola de sorvete","descricao":null,"nivel":null,"energia":null,"detalhes":[],"tags":["brownie","sorvete"]},{"id":"doce-milkshake","titulo":"Milkshake pequeno","descricao":"Bob''s, McDonald''s.","nivel":null,"energia":{"kcal":330,"mostrarKcal":false,"observacao":null},"detalhes":[],"tags":["milkshake"]},{"id":"doce-acai","titulo":"Açaí de 300 ml com 1 fruta e leite condensado","descricao":null,"nivel":null,"energia":null,"detalhes":[],"tags":["acai"]}]}],"lembretes":[]}'::jsonb, array['doce', 'sobremesa', 'chocolate', 'bolo', 'sorvete', 'cookie']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('subway', 'comer_fora', 'Subway', null, null, 'sanduiche', 8, 'rascunho', '{"introducao":null,"decisoes":[],"lembretes":[]}'::jsonb, array['subway', 'sanduiche', 'sub']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('restaurantes', 'comer_fora', 'Restaurantes', null, null, 'restaurante', 9, 'rascunho', '{"introducao":null,"decisoes":[],"lembretes":[]}'::jsonb, array['restaurante', 'self service', 'buffet', 'por quilo']::text[]) on conflict (id) do nothing;
insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values ('delivery', 'comer_fora', 'Delivery', null, null, 'delivery', 10, 'rascunho', '{"introducao":null,"decisoes":[],"lembretes":[]}'::jsonb, array['delivery', 'ifood', 'entrega']::text[]) on conflict (id) do nothing;

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
