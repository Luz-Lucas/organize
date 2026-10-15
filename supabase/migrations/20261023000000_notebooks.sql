-- Caderno com S Pen: tipo de nota, páginas manuscritas e bucket de imagens.
-- O documento da página (data) é JSON v1 → gzip → base64; o servidor só guarda o texto e limita o tamanho.

alter table public.notes
  add column kind text not null default 'text' check (kind in ('text', 'notebook'));

create table public.note_pages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  note_id uuid not null references public.notes (id) on delete cascade,
  idx integer not null check (idx >= 0),
  background text not null default 'lined' check (background in ('blank', 'lined', 'grid', 'dots')),
  data text not null default '' check (octet_length(data) <= 4000000),
  recognized_text text not null default '',
  version integer not null default 0,
  updated_at timestamptz not null default now(),
  -- adiada: permite reordenar (trocar idx) numa única transação.
  -- Atenção: constraint deferrable não serve de alvo para `on conflict`; use insert/update separados.
  constraint note_pages_note_idx_uq unique (note_id, idx) deferrable initially deferred
);
create index note_pages_user_idx on public.note_pages (user_id);

alter table public.note_pages enable row level security;
revoke all on public.note_pages from anon;

-- A página é do dono E a nota também precisa ser dele (a FK sozinha não impede apontar para nota alheia).
create policy "dono" on public.note_pages for all to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.notes n where n.id = note_id and n.user_id = (select auth.uid()))
  );

create trigger touch_updated_at before update on public.note_pages
  for each row execute function public.touch_updated_at();

alter publication supabase_realtime add table public.note_pages;

-- Imagens do caderno: bucket privado; caminho <user_id>/<note_id>/<uuid>.<ext>; só o dono (prefixo) acessa.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'notebook-images', 'notebook-images', false, 10485760,
  array['image/png', 'image/jpeg', 'image/webp', 'image/gif', 'image/heic', 'image/heif']
)
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create policy "caderno: dono lê imagens" on storage.objects for select to authenticated
  using (bucket_id = 'notebook-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "caderno: dono envia imagens" on storage.objects for insert to authenticated
  with check (bucket_id = 'notebook-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "caderno: dono atualiza imagens" on storage.objects for update to authenticated
  using (bucket_id = 'notebook-images' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'notebook-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "caderno: dono apaga imagens" on storage.objects for delete to authenticated
  using (bucket_id = 'notebook-images' and (storage.foldername(name))[1] = (select auth.uid())::text);
