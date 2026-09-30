create table public.wake_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  label text not null check (length(btrim(label)) > 0),
  days smallint[] not null check (cardinality(days) > 0 and days <@ array[1, 2, 3, 4, 5, 6, 7]::smallint[]),
  time time not null,
  echo_device_id text not null check (length(echo_device_id) > 0),
  spotify_query text,
  music_first boolean not null default true,
  briefing_delay_min integer not null default 3 check (briefing_delay_min between 0 and 30),
  volume integer not null default 30 check (volume between 0 and 100),
  fallback_alarm boolean not null default true,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.wake_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  plan_id uuid references public.wake_plans (id) on delete set null,
  run_date date not null,
  planned_for timestamptz not null,
  status text not null check (status in ('armed', 'running', 'done', 'failed', 'missed', 'cancelled')),
  fallback_handle text,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (plan_id, run_date)
);

create table public.alexa_commands (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  kind text not null check (kind in ('device', 'routine', 'speak', 'music', 'sync', 'wake_test')),
  payload jsonb not null default '{}',
  status text not null default 'pending' check (status in ('pending', 'running', 'done', 'failed', 'expired')),
  result text,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz
);
create index alexa_commands_pending_idx on public.alexa_commands (user_id, created_at) where status = 'pending';

create table public.alexa_devices (
  user_id uuid not null references auth.users (id) on delete cascade,
  id text not null,
  name text not null,
  kind text not null check (kind in ('echo', 'smart')),
  operations text[] not null default '{}',
  online boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

create table public.alexa_routines (
  user_id uuid not null references auth.users (id) on delete cascade,
  id text not null,
  name text not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

create table public.alexa_bridge_status (
  user_id uuid primary key references auth.users (id) on delete cascade,
  state text not null check (state in ('ok', 'auth_required', 'error')),
  message text,
  last_seen timestamptz not null default now()
);

create trigger touch_updated_at before update on public.wake_plans
  for each row execute function public.touch_updated_at();
create trigger touch_updated_at before update on public.wake_runs
  for each row execute function public.touch_updated_at();

alter table public.wake_plans enable row level security;
alter table public.wake_runs enable row level security;
alter table public.alexa_commands enable row level security;
alter table public.alexa_devices enable row level security;
alter table public.alexa_routines enable row level security;
alter table public.alexa_bridge_status enable row level security;

create policy "dono" on public.wake_plans for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "lê próprio" on public.wake_runs for select to authenticated
  using (user_id = (select auth.uid()));
create policy "lê próprio" on public.alexa_commands for select to authenticated
  using (user_id = (select auth.uid()));
create policy "enfileira próprio" on public.alexa_commands for insert to authenticated
  with check (user_id = (select auth.uid()) and status = 'pending');
create policy "lê próprio" on public.alexa_devices for select to authenticated
  using (user_id = (select auth.uid()));
create policy "lê próprio" on public.alexa_routines for select to authenticated
  using (user_id = (select auth.uid()));
create policy "lê próprio" on public.alexa_bridge_status for select to authenticated
  using (user_id = (select auth.uid()));

create or replace function public.claim_wake_run(p_user uuid, p_plan uuid, p_date date, p_planned timestamptz)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  affected integer;
begin
  insert into public.wake_runs (user_id, plan_id, run_date, planned_for, status)
  values (p_user, p_plan, p_date, p_planned, 'running')
  on conflict (plan_id, run_date) do update
    set status = 'running'
    where public.wake_runs.status in ('armed', 'cancelled');
  get diagnostics affected = row_count;
  return affected > 0;
end;
$$;

create or replace function public.claim_command(p_id uuid)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  affected integer;
begin
  update public.alexa_commands set status = 'running', started_at = now()
  where id = p_id and status = 'pending';
  get diagnostics affected = row_count;
  return affected > 0;
end;
$$;

alter publication supabase_realtime add table
  public.wake_plans, public.alexa_commands, public.alexa_devices,
  public.alexa_routines, public.alexa_bridge_status;
