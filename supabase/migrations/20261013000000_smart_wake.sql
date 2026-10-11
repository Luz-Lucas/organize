-- Despertar inteligente (fase 1): localização do celular, "minha casa", clima,
-- ações de dispositivos na rotina, espera do resumo em segundos e status 'skipped'.

-- Última localização reportada pelo celular (uma linha por usuário).
create table public.user_locations (
  user_id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  lat double precision not null check (lat between -90 and 90),
  lon double precision not null check (lon between -180 and 180),
  accuracy_m real check (accuracy_m >= 0),
  reported_at timestamptz not null default now()
);
alter table public.user_locations enable row level security;
create policy "dono" on public.user_locations for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Minha casa e presença.
alter table public.user_settings
  add column home_lat double precision
    constraint user_settings_home_lat_check check (home_lat between -90 and 90),
  add column home_lon double precision
    constraint user_settings_home_lon_check check (home_lon between -180 and 180),
  add column home_radius_m integer not null default 50
    constraint user_settings_home_radius_m_check check (home_radius_m between 20 and 500),
  add column require_home boolean not null default true,
  add constraint user_settings_home_pair_check check ((home_lat is null) = (home_lon is null));

-- Despertar: clima, ações de dispositivos, alarme no celular (usado na fase 2) e espera em segundos.
alter table public.wake_plans
  add column include_weather boolean not null default true,
  add column device_actions jsonb not null default '[]'::jsonb
    constraint wake_plans_device_actions_check check (jsonb_typeof(device_actions) = 'array'),
  add column phone_alarm text not null default 'fallback'
    constraint wake_plans_phone_alarm_check check (phone_alarm in ('never', 'fallback', 'always')),
  add column briefing_delay_sec integer
    constraint wake_plans_briefing_delay_sec_check check (briefing_delay_sec between 0 and 1800);

-- Execução pulada porque o usuário estava fora de casa.
alter table public.wake_runs drop constraint wake_runs_status_check;
alter table public.wake_runs add constraint wake_runs_status_check
  check (status in ('armed', 'running', 'done', 'failed', 'missed', 'cancelled', 'skipped'));
