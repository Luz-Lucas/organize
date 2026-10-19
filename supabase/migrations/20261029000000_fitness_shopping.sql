-- Academia (fichas, sessões e séries) e Compras (listas, itens e frequentes).
-- Todas as tabelas são do dono (RLS "dono"); as filhas só aceitam pai do mesmo dono, porque a FK
-- sozinha não impede apontar para ficha/sessão/lista alheia (mesmo cuidado de events.tag_id).

-- ===== Academia ===========================================================
create table public.workouts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 60),
  position integer not null default 0,
  created_at timestamptz not null default now()
);

create table public.workout_exercises (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  workout_id uuid not null references public.workouts (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  sets integer not null default 3 check (sets between 1 and 20),
  reps text not null default '10' check (char_length(reps) between 1 and 20),
  load_kg numeric(6, 2) check (load_kg >= 0),
  rest_seconds integer not null default 90 check (rest_seconds between 0 and 900),
  notes text not null default '',
  position integer not null default 0
);
create index workout_exercises_workout_idx on public.workout_exercises (workout_id);

-- Apagar a ficha mantém a sessão (histórico); o nome fica em workout_name.
create table public.workout_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  workout_id uuid references public.workouts (id) on delete set null,
  workout_name text not null check (char_length(workout_name) between 1 and 60),
  day date not null,
  started_at timestamptz not null default now(),
  finished_at timestamptz
);
create index workout_sessions_user_day_idx on public.workout_sessions (user_id, day desc);
create index workout_sessions_workout_idx on public.workout_sessions (workout_id) where workout_id is not null;

-- Apagar o exercício mantém a série; o nome fica em exercise_name.
create table public.set_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  session_id uuid not null references public.workout_sessions (id) on delete cascade,
  exercise_id uuid references public.workout_exercises (id) on delete set null,
  exercise_name text not null check (char_length(exercise_name) between 1 and 80),
  set_index integer not null check (set_index >= 1),
  reps integer check (reps between 0 and 999),
  load_kg numeric(6, 2),
  done_at timestamptz not null default now(),
  unique (session_id, exercise_id, set_index)
);
create index set_logs_user_exercise_idx on public.set_logs (user_id, exercise_id, done_at desc);
create index set_logs_exercise_idx on public.set_logs (exercise_id) where exercise_id is not null;

-- ===== Compras ============================================================
create table public.shopping_lists (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 40),
  position integer not null default 0,
  section_order text[] check (section_order <@ array['hortifruti', 'padaria', 'acougue', 'frios', 'mercearia',
                                                      'bebidas', 'limpeza', 'higiene', 'congelados', 'outros']),
  created_at timestamptz not null default now()
);
create unique index shopping_lists_user_name_uq on public.shopping_lists (user_id, lower(name));

-- `section` pode vir nula no insert: o gatilho before insert a preenche (por isso not null vale).
create table public.shopping_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  list_id uuid not null references public.shopping_lists (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  quantity text not null default '' check (char_length(quantity) <= 30),
  section text not null check (section in ('hortifruti', 'padaria', 'acougue', 'frios', 'mercearia',
                                           'bebidas', 'limpeza', 'higiene', 'congelados', 'outros')),
  checked boolean not null default false,
  position integer not null default 0,
  created_at timestamptz not null default now()
);
create index shopping_items_list_idx on public.shopping_items (list_id);

-- Itens já comprados: alimentam sugestões, "Comprar de novo" e a seção lembrada. name_key = nome sem caixa/acento.
create table public.shopping_frequent (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name_key text not null check (char_length(name_key) between 1 and 80),
  name text not null check (char_length(name) between 1 and 80),
  section text not null check (section in ('hortifruti', 'padaria', 'acougue', 'frios', 'mercearia',
                                           'bebidas', 'limpeza', 'higiene', 'congelados', 'outros')),
  times integer not null default 1,
  last_added_at timestamptz not null default now(),
  unique (user_id, name_key)
);

-- ===== RLS, anon e realtime ===============================================
do $$
declare
  t text;
begin
  foreach t in array array['workouts', 'workout_exercises', 'workout_sessions', 'set_logs',
                           'shopping_lists', 'shopping_items', 'shopping_frequent']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('alter publication supabase_realtime add table public.%I', t);
  end loop;
end $$;

create policy "dono" on public.workouts for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "dono" on public.workout_exercises for all to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.workouts w where w.id = workout_id and w.user_id = (select auth.uid()))
  );

create policy "dono" on public.workout_sessions for all to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and (workout_id is null
         or exists (select 1 from public.workouts w where w.id = workout_id and w.user_id = (select auth.uid())))
  );

create policy "dono" on public.set_logs for all to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.workout_sessions s where s.id = session_id and s.user_id = (select auth.uid()))
    and (exercise_id is null
         or exists (select 1 from public.workout_exercises x where x.id = exercise_id and x.user_id = (select auth.uid())))
  );

create policy "dono" on public.shopping_lists for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "dono" on public.shopping_items for all to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.shopping_lists l where l.id = list_id and l.user_id = (select auth.uid()))
  );

create policy "dono" on public.shopping_frequent for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ===== Seção do item ======================================================
-- Chave do frequente: minúsculo, sem acento e sem espaços sobrando.
create or replace function public.shopping_name_key(t text)
returns text
language sql
immutable
set search_path = ''
as $$
  select regexp_replace(public.fold_event_text(btrim(t)), '\s+', ' ', 'g');
$$;

-- Palpite de seção: 1) a que o usuário já usou para esse nome; 2) palavras-chave (a primeira seção
-- da lista que casar; as mais específicas vêm antes, ex.: "água sanitária" é limpeza e não bebida);
-- 3) outros. Palavra inteira (\m...\M, com plural simples) para "maca" não casar "macarrao" nem "ovo" "novo".
create or replace function public.guess_shopping_section(uid uuid, item text)
returns text
language sql
stable
set search_path = ''
as $$
  with k as (select public.shopping_name_key(item) as key)
  select coalesce(
    (select f.section from public.shopping_frequent f, k where f.user_id = uid and f.name_key = k.key),
    (select v.section
       from (values
         (1,  'limpeza',    'detergente|sabao|amaciante|desinfetante|esponja|agua sanitaria'),
         (2,  'higiene',    'sabonete|shampoo|xampu|pasta de dente|escova|papel higienico|desodorante'),
         (3,  'congelados', 'sorvete|congelad[oa]s?|pizza'),
         (4,  'mercearia',  'arroz|feijao|macarrao|oleo|acucar|sal|farinha|molho'),
         (5,  'bebidas',    'agua|suco|refrigerante|cerveja|vinho|cafe'),
         (6,  'padaria',    'pao|paes|bolo|torrada|biscoito|bolacha'),
         (7,  'acougue',    'carne|frango|peixe|linguica|bife|costela'),
         (8,  'frios',      'leite|queijo|presunto|iogurte|manteiga|requeijao|ovo'),
         (9,  'hortifruti', 'banana|maca|tomate|alface|cebola|alho|batata|cenoura|limao|limoes|laranja|fruta|verdura|legume')
       ) as v(ord, section, words), k
      where k.key ~ ('\m(' || v.words || ')s?\M')
      order by v.ord
      limit 1),
    'outros');
$$;

-- Gatilhos rodam como dono da função (security definer): fold_event_text, guess e shopping_frequent
-- não são chamáveis pelo app, e o user_id já foi validado pela RLS do item.
create or replace function public.shopping_items_guess_section()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.section is null then
    new.section := public.guess_shopping_section(new.user_id, new.name);
  end if;
  return new;
end;
$$;

create or replace function public.shopping_items_track_frequent()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.shopping_frequent (user_id, name_key, name, section, times, last_added_at)
  values (new.user_id, public.shopping_name_key(new.name), new.name, new.section, 1, now())
  on conflict (user_id, name_key) do update
    set times = public.shopping_frequent.times + 1,
        name = excluded.name,
        section = excluded.section,
        last_added_at = now();
  return new;
end;
$$;

-- Corrigir a seção de um item: o app lembra para os próximos com o mesmo nome.
create or replace function public.shopping_items_learn_section()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.shopping_frequent
     set section = new.section
   where user_id = new.user_id and name_key = public.shopping_name_key(new.name);
  return new;
end;
$$;

create trigger shopping_items_guess_section before insert on public.shopping_items
  for each row execute function public.shopping_items_guess_section();
create trigger shopping_items_track_frequent after insert on public.shopping_items
  for each row execute function public.shopping_items_track_frequent();
create trigger shopping_items_learn_section after update of section on public.shopping_items
  for each row when (old.section is distinct from new.section)
  execute function public.shopping_items_learn_section();

revoke all on function public.shopping_name_key(text) from public, anon, authenticated;
revoke all on function public.guess_shopping_section(uuid, text) from public, anon, authenticated;
revoke all on function public.shopping_items_guess_section() from public, anon, authenticated;
revoke all on function public.shopping_items_track_frequent() from public, anon, authenticated;
revoke all on function public.shopping_items_learn_section() from public, anon, authenticated;
