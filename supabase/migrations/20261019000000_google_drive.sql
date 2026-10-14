-- Google Drive (Documentos). Reaproveita google_accounts (refresh token CIFRADO, só service role)
-- com provider 'drive' e adiciona drive_state, que o app lê (somente leitura) e só o servidor escreve.

alter table public.google_accounts drop constraint google_accounts_provider_check;
alter table public.google_accounts
  add constraint google_accounts_provider_check check (provider in ('gmail', 'drive'));

create table public.drive_state (
  user_id uuid primary key references auth.users (id) on delete cascade,
  account_email text,
  status text not null default 'not_connected'
    check (status in ('not_connected', 'ok', 'auth_required', 'error')),
  root_folder_id text,
  message text,
  connected_at timestamptz
);

alter table public.drive_state enable row level security;

-- O cliente só lê a própria linha; nunca escreve.
revoke all on public.drive_state from anon, authenticated;
grant select on public.drive_state to authenticated;

create policy "dono lê" on public.drive_state for select to authenticated
  using (user_id = (select auth.uid()));

alter publication supabase_realtime add table public.drive_state;
