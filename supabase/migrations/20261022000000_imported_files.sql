-- Arquivos importados de pastas vigiadas (Samsung Notes) e de outras origens.
-- O sha256 do CONTEÚDO é a chave de deduplicação: o mesmo arquivo exportado no celular e no
-- tablet só sobe uma vez para o Drive e gera uma única nota-link.

create table public.imported_files (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  name text not null,
  size_bytes bigint not null check (size_bytes >= 0),
  source text not null default 'samsung_notes' check (source in ('samsung_notes', 'import', 'share')),
  drive_file_id text,
  note_id uuid references public.notes (id) on delete set null,
  device text,
  created_at timestamptz not null default now(),
  primary key (user_id, sha256)
);

create index imported_files_note_idx on public.imported_files (note_id);

alter table public.imported_files enable row level security;

-- O cliente lê, grava e atualiza só os próprios registros; nunca apaga.
revoke all on public.imported_files from anon, authenticated;
grant select, insert, update on public.imported_files to authenticated;

create policy "dono lê" on public.imported_files for select to authenticated
  using (user_id = (select auth.uid()));
create policy "dono grava" on public.imported_files for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "dono atualiza" on public.imported_files for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

alter publication supabase_realtime add table public.imported_files;
