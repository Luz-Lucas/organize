-- Notificações do Gmail (somente leitura, escopo gmail.metadata: só cabeçalhos).
-- google_accounts guarda o refresh token CIFRADO e só é acessível pela service role
-- (Edge Functions). O app lê apenas email_state e email_items, que só o servidor escreve.

create table public.google_accounts (
  user_id uuid not null references auth.users (id) on delete cascade,
  provider text not null check (provider in ('gmail')),
  account_email text not null,
  refresh_token_enc text not null,
  scopes text not null,
  connected_at timestamptz not null default now(),
  primary key (user_id, provider)
);

create table public.email_state (
  user_id uuid primary key references auth.users (id) on delete cascade,
  account_email text,
  unread_count integer not null default 0 check (unread_count >= 0),
  status text not null default 'not_connected'
    check (status in ('not_connected', 'ok', 'auth_required', 'error')),
  last_synced_at timestamptz,
  message text
);

create table public.email_items (
  user_id uuid not null references auth.users (id) on delete cascade,
  gmail_id text not null,
  thread_id text,
  from_name text,
  from_addr text,
  subject text,
  received_at timestamptz,
  unread boolean not null default false,
  primary key (user_id, gmail_id)
);
create index email_items_recent_idx on public.email_items (user_id, received_at desc);

alter table public.google_accounts enable row level security;
alter table public.email_state enable row level security;
alter table public.email_items enable row level security;

-- google_accounts: nenhuma policy e nenhum privilégio para os papéis da API.
revoke all on public.google_accounts from anon, authenticated;

-- email_state / email_items: o cliente só lê as próprias linhas; nunca escreve.
revoke all on public.email_state, public.email_items from anon, authenticated;
grant select on public.email_state, public.email_items to authenticated;

create policy "dono lê" on public.email_state for select to authenticated
  using (user_id = (select auth.uid()));
create policy "dono lê" on public.email_items for select to authenticated
  using (user_id = (select auth.uid()));

alter publication supabase_realtime add table public.email_state, public.email_items;

-- Sincronização a cada 10 minutos. Segredos no Vault: 'gmail_sync_url' (URL da função
-- gmail-sync) e 'cron_secret' (o mesmo do news-fetch). Sem eles o job roda sem efeito.
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

select cron.schedule(
  'gmail-sync',
  '*/10 * * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'gmail_sync_url'),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
  $$
);
