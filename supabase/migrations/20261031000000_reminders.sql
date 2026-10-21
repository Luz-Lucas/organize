-- Lembretes de tarefas e eventos (celular e Alexa).
-- `reminders` guarda quantos minutos antes avisar: 1440 (1 dia), 60 (1 hora), 30 e 15; vários ao mesmo tempo, sem repetir.
-- Padrão: tarefa = {60}, evento = {30} (vale também para o que já existe, pelo default da coluna).

create function public.reminders_valid(r smallint[])
returns boolean
language sql
immutable
set search_path = ''
as $$
  select r is not null
    and r <@ array[1440, 60, 30, 15]::smallint[]
    and cardinality(r) = (select count(distinct x) from unnest(r) as x);
$$;

alter table public.tasks
  add column reminders smallint[] not null default '{60}',
  add constraint tasks_reminders_check check (public.reminders_valid(reminders));

alter table public.events
  add column reminders smallint[] not null default '{30}',
  add constraint events_reminders_check check (public.reminders_valid(reminders));

-- Preferências por conta. Não perturbe atravessa a meia-noite (23:00 → 10:00).
alter table public.user_settings
  add column reminders_phone boolean not null default true,
  add column reminders_alexa boolean not null default true,
  add column reminder_echo text,
  add column dnd_enabled boolean not null default true,
  add column dnd_start time not null default '23:00',
  add column dnd_end time not null default '10:00';

-- Registro dos avisos já falados pela ponte (evita repetir). Só a ponte (service role) escreve.
create table public.reminder_deliveries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('task', 'event')),
  item_id uuid not null,
  fire_at timestamptz not null,
  channel text not null check (channel in ('alexa')),
  created_at timestamptz not null default now(),
  unique (user_id, kind, item_id, fire_at, channel)
);
create index reminder_deliveries_fire_idx on public.reminder_deliveries (fire_at);

alter table public.reminder_deliveries enable row level security;
create policy "lê próprio" on public.reminder_deliveries for select to authenticated
  using (user_id = (select auth.uid()));
