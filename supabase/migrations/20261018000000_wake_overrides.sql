-- Exceções de um dia só para os despertares ("só amanhã"): pular ou mudar o horário.
-- A ponte lê esta tabela com a service role; o app grava como o dono.

create table public.wake_overrides (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  plan_id uuid not null references public.wake_plans (id) on delete cascade,
  run_date date not null,
  skip boolean not null default false,
  time time,
  created_at timestamptz not null default now(),
  primary key (plan_id, run_date),
  constraint wake_overrides_skip_or_time_check check (skip or time is not null)
);

create index wake_overrides_user_date_idx on public.wake_overrides (user_id, run_date);

alter table public.wake_overrides enable row level security;

-- O plano apontado precisa ser do mesmo usuário (impede ligar a exceção a um despertar alheio).
create policy "lê próprio" on public.wake_overrides for select to authenticated
  using (user_id = (select auth.uid()));
create policy "cria próprio" on public.wake_overrides for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.wake_plans p where p.id = plan_id and p.user_id = (select auth.uid()))
  );
create policy "altera próprio" on public.wake_overrides for update to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.wake_plans p where p.id = plan_id and p.user_id = (select auth.uid()))
  );
create policy "apaga próprio" on public.wake_overrides for delete to authenticated
  using (user_id = (select auth.uid()));

alter publication supabase_realtime add table public.wake_overrides;
