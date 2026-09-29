create type public.space_kind as enum ('materia', 'trabalho', 'hobby', 'geral');
create type public.task_status as enum ('todo', 'doing', 'done');

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.spaces (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null check (length(btrim(name)) > 0),
  kind public.space_kind not null default 'geral',
  icon text,
  color text,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  space_id uuid references public.spaces (id) on delete cascade,
  parent_id uuid references public.notes (id) on delete cascade,
  title text not null check (length(btrim(title)) > 0),
  body text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index notes_user_title_uq
  on public.notes (user_id, lower(regexp_replace(btrim(title), '\s+', ' ', 'g')));
create index notes_space_idx on public.notes (space_id);

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  space_id uuid references public.spaces (id) on delete cascade,
  note_id uuid references public.notes (id) on delete set null,
  title text not null check (length(btrim(title)) > 0),
  description text not null default '',
  status public.task_status not null default 'todo',
  due_at timestamptz,
  completed_at timestamptz,
  source text not null default 'manual',
  external_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index tasks_external_uq on public.tasks (user_id, source, external_id) where external_id is not null;
create index tasks_due_idx on public.tasks (user_id, due_at);

create table public.events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  space_id uuid references public.spaces (id) on delete set null,
  title text not null check (length(btrim(title)) > 0),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  all_day boolean not null default false,
  location text,
  source text not null default 'manual',
  external_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at >= starts_at)
);
create unique index events_external_uq on public.events (user_id, source, external_id) where external_id is not null;
create index events_range_idx on public.events (user_id, starts_at, ends_at);

do $$
declare t text;
begin
  foreach t in array array['spaces', 'notes', 'tasks', 'events'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy "dono" on public.%I for all to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))',
      t);
    execute format(
      'create trigger touch_updated_at before update on public.%I for each row execute function public.touch_updated_at()',
      t);
  end loop;
end $$;

alter publication supabase_realtime add table public.spaces, public.notes, public.tasks, public.events;
