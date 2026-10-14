-- Etiquetas coloridas da agenda (aulas, academia, sazonais, reuniões).
-- `role` dá o peso visual no calendário (main = destaque, secondary = discreto) e é o que a
-- classificação automática usa para achar a etiqueta certa do usuário, mesmo se ela for renomeada.

create table public.event_tags (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 40),
  color text not null check (color ~ '^#[0-9A-Fa-f]{6}$'),
  role text not null default 'normal' check (role in ('main', 'secondary', 'seasonal', 'meeting', 'normal')),
  position integer not null default 0,
  created_at timestamptz not null default now()
);
-- unique (user_id, lower(name)): constraint de tabela não aceita expressão, então é índice único.
create unique index event_tags_user_name_uq on public.event_tags (user_id, lower(name));

alter table public.event_tags enable row level security;
revoke all on public.event_tags from anon;
create policy "dono" on public.event_tags for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

alter publication supabase_realtime add table public.event_tags;

-- Excluir a etiqueta deixa os eventos sem etiqueta.
alter table public.events add column tag_id uuid references public.event_tags (id) on delete set null;
create index events_tag_idx on public.events (tag_id) where tag_id is not null;

-- A FK sozinha não impede apontar para etiqueta alheia: o evento só pode usar etiqueta do próprio dono.
drop policy "dono" on public.events;
create policy "dono" on public.events for all to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and (tag_id is null
         or exists (select 1 from public.event_tags t where t.id = tag_id and t.user_id = (select auth.uid())))
  );

-- ---------------------------------------------------------------------------
-- Semeadura: cria as etiquetas iniciais que faltam (por papel). Idempotente.
-- Devolve quantas criou. Cores da paleta fixa das pastas do app.
-- ---------------------------------------------------------------------------
create or replace function public.seed_event_tags(uid uuid)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  n integer;
begin
  with wanted(name, color, role, position) as (
    values
      ('Aula', '#3E63DD', 'main', 0),
      ('Academia', '#30A46C', 'secondary', 1),
      ('Sazonal', '#FFB224', 'seasonal', 2),
      ('Reunião', '#8E4EC6', 'meeting', 3)
  ), ins as (
    insert into public.event_tags (user_id, name, color, role, position)
    select uid, w.name, w.color, w.role, w.position
      from wanted w
     where not exists (select 1 from public.event_tags t where t.user_id = uid and t.role = w.role)
    on conflict do nothing
    returning 1
  )
  select count(*) into n from ins;
  return n;
end;
$$;

-- Minúsculas e sem acentos (lower() sozinho não depende do locale do banco porque os acentos são trocados antes).
create or replace function public.fold_event_text(t text)
returns text
language sql
immutable
set search_path = ''
as $$
  select lower(translate(t,
    'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüç',
    'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc'));
$$;

-- Classifica os eventos do usuário que ainda não têm etiqueta, pela primeira regra que casar:
--   1. Aula (main): título que começa com código de matéria (^[A-Z][0-9]{2}\y, ex.: M02, C03) ou com "Estudo";
--   2. Academia (secondary): título com "academia";
--   3. Reunião (meeting): "reunião"/"reuniao"/"cogestão"/"cogestao" ou começa com "NP"/"ReuNP";
--   4. Sazonal (seasonal): evento de dia inteiro, ou título com viagem, feriado ou "fora da cidade".
-- (3 e 4 ignoram caixa e acentos.) O resto fica sem etiqueta. Usa a etiqueta do usuário pelo papel
-- (a de menor position se houver mais de uma); sem etiqueta do papel, a regra não faz nada.
-- Devolve quantos eventos etiquetou. Idempotente.
create or replace function public.classify_events(uid uuid)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  total integer := 0;
  n integer;
  r record;
begin
  for r in
    select * from (values
      (1, 'main',      'e.title ~ ''^\s*[A-Z][0-9]{2}\y'' or public.fold_event_text(e.title) ~ ''^\s*estudo'''),
      (2, 'secondary', 'public.fold_event_text(e.title) ~ ''academia'''),
      (3, 'meeting',   'public.fold_event_text(e.title) ~ ''(reuniao|cogestao)'' or public.fold_event_text(e.title) ~ ''^\s*(np|reunp)'''),
      (4, 'seasonal',  'e.all_day or public.fold_event_text(e.title) ~ ''(viagem|feriado|fora da cidade)''')
    ) as v(ord, role, cond) order by ord
  loop
    execute format($f$
      update public.events e
         set tag_id = (select t.id from public.event_tags t
                        where t.user_id = $1 and t.role = $2
                        order by t.position, t.created_at, t.id limit 1)
       where e.user_id = $1 and e.tag_id is null and (%s)
         and exists (select 1 from public.event_tags t where t.user_id = $1 and t.role = $2)
    $f$, r.cond) using uid, r.role;
    get diagnostics n = row_count;
    total := total + n;
  end loop;
  return total;
end;
$$;

-- RPC do app: semeia e classifica os eventos de quem chama. Devolve quantas etiquetas criou.
create or replace function public.seed_my_event_tags()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  n integer;
begin
  if uid is null then
    raise exception 'não autenticado' using errcode = '42501';
  end if;
  n := public.seed_event_tags(uid);
  perform public.classify_events(uid);
  return n;
end;
$$;

revoke all on function public.seed_event_tags(uuid) from public, anon, authenticated;
revoke all on function public.classify_events(uuid) from public, anon, authenticated;
revoke all on function public.fold_event_text(text) from public, anon, authenticated;
revoke all on function public.seed_my_event_tags() from public, anon;
grant execute on function public.seed_my_event_tags() to authenticated;

-- Usuários existentes: etiquetas iniciais e classificação dos eventos atuais.
select public.seed_event_tags(id) from auth.users;
select public.classify_events(id) from auth.users;
