-- Atualização do app por dentro: cada versão publicada (tool/release.sh) vira uma linha em app_releases
-- e um arquivo no bucket privado app-releases. O app autenticado só LÊ; quem grava é o service role
-- (que ignora RLS), usado só pelo script de publicação nesta máquina.

create table public.app_releases (
  id uuid primary key default gen_random_uuid(),
  platform text not null check (platform in ('android', 'linux', 'windows')),
  version text not null check (char_length(version) between 1 and 40),
  build integer not null check (build > 0),
  storage_path text not null check (char_length(storage_path) between 1 and 300),
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  size_bytes bigint not null check (size_bytes > 0),
  notes text not null default '',
  created_at timestamptz not null default now(),
  unique (platform, build)
);

alter table public.app_releases enable row level security;
-- Sem policy de escrita e sem privilégio de escrita: a defesa é dupla.
revoke all on public.app_releases from anon, authenticated;
grant select on public.app_releases to authenticated;
create policy "autenticado lê releases" on public.app_releases for select to authenticated using (true);

-- Bucket privado (200 MB por arquivo). Leitura só para autenticados (gera a URL assinada de curta duração);
-- sem policy de insert/update/delete: só o service role escreve.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('app-releases', 'app-releases', false, 209715200, null)
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create policy "releases: autenticado lê" on storage.objects for select to authenticated
  using (bucket_id = 'app-releases');
