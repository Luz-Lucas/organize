-- Redesign de interface: configurações por usuário (tema, dispositivos ocultos),
-- quadro de avisos e comando delete_device da ponte da Alexa.
create table public.user_settings (
  user_id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  theme text not null default 'violeta'
    check (theme in ('violeta','safira','musgo','lunar','indigo','grafite','coral','cobalto','cacto','bronze')),
  hidden_alexa_devices text[] not null default '{}',
  updated_at timestamptz not null default now()
);
create table public.notices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title text not null check (length(btrim(title)) > 0),
  body text not null default '',
  priority text not null default 'normal' check (priority in ('normal', 'alta')),
  pinned boolean not null default false,
  expires_at timestamptz,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index notices_active_idx on public.notices (user_id, archived_at);
create trigger touch_updated_at before update on public.user_settings
  for each row execute function public.touch_updated_at();
create trigger touch_updated_at before update on public.notices
  for each row execute function public.touch_updated_at();
alter table public.user_settings enable row level security;
alter table public.notices enable row level security;
create policy "dono" on public.user_settings for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "dono" on public.notices for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
alter publication supabase_realtime add table public.user_settings, public.notices;
alter table public.alexa_commands drop constraint alexa_commands_kind_check;
alter table public.alexa_commands add constraint alexa_commands_kind_check
  check (kind in ('device', 'routine', 'speak', 'music', 'sync', 'wake_test', 'delete_device'));
