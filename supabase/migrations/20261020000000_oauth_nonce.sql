-- Nonces do `state` do OAuth do Google (Gmail e Drive): cada state só conecta uma vez.
-- Só o service role (Edge Function gmail-callback) usa; anon/authenticated não enxergam nada.

create table public.oauth_state_nonces (
  nonce text primary key check (char_length(nonce) between 1 and 200),
  used_at timestamptz not null default now()
);

create index oauth_state_nonces_used_at_idx on public.oauth_state_nonces (used_at);

alter table public.oauth_state_nonces enable row level security;
revoke all on public.oauth_state_nonces from anon, authenticated;
grant select, insert, delete on public.oauth_state_nonces to service_role;

-- Registra o nonce. Devolve true se era novo; false se já tinha sido usado (conflito).
-- Aproveita para apagar nonces com mais de 1 dia (o state vale só 10 minutos).
create function public.consume_oauth_nonce(p_nonce text)
returns boolean
language plpgsql
set search_path = ''
as $$
declare
  inserted integer;
begin
  delete from public.oauth_state_nonces where used_at < now() - interval '1 day';
  insert into public.oauth_state_nonces (nonce) values (p_nonce) on conflict (nonce) do nothing;
  get diagnostics inserted = row_count;
  return inserted = 1;
end;
$$;

revoke all on function public.consume_oauth_nonce(text) from public, anon, authenticated;
grant execute on function public.consume_oauth_nonce(text) to service_role;
