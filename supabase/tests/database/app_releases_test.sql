begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111', 'a@test.dev');

-- Fixtures (papel postgres, que ignora RLS: faz o papel do service role)
insert into app_releases (platform, version, build, storage_path, sha256, size_bytes, notes) values
  ('android', '1.0.1', 2, 'android/2/organizacional.apk', repeat('a', 64), 1000, 'Corrige o widget'),
  ('android', '1.0.2', 3, 'android/3/organizacional.apk', repeat('b', 64), 2000, 'Novo caderno'),
  ('linux',   '1.0.2', 3, 'linux/3/organizacional.tar.gz', repeat('c', 64), 3000, '');

select is((select public from storage.buckets where id = 'app-releases'), false, 'bucket app-releases é privado');
select is((select file_size_limit from storage.buckets where id = 'app-releases'), 209715200::bigint,
  'bucket limita cada arquivo a 200 MB');
select is((select notes from app_releases where platform = 'linux'), '', 'notes tem default vazio');

select throws_ok(
  $$ insert into app_releases (platform, version, build, storage_path, sha256, size_bytes)
     values ('ios', '1.0.0', 1, 'ios/1/x', repeat('a', 64), 1) $$,
  '23514', null, 'plataforma fora de android/linux/windows é recusada');
select throws_ok(
  $$ insert into app_releases (platform, version, build, storage_path, sha256, size_bytes)
     values ('windows', '1.0.0', 1, 'windows/1/x', 'XYZ', 1) $$,
  '23514', null, 'sha256 que não é hexa minúsculo de 64 caracteres é recusado');
select throws_ok(
  $$ insert into app_releases (platform, version, build, storage_path, sha256, size_bytes)
     values ('android', '1.0.9', 3, 'android/3/outro.apk', repeat('d', 64), 1) $$,
  '23505', null, 'unique (platform, build) impede duas releases com o mesmo build');
select lives_ok(
  $$ insert into app_releases (platform, version, build, storage_path, sha256, size_bytes)
     values ('windows', '1.0.2', 3, 'windows/3/o.zip', repeat('e', 64), 4000) $$,
  'o mesmo build pode existir em outra plataforma');

-- Usuário autenticado: lê, não escreve
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select is((select count(*) from app_releases)::int, 4, 'autenticado lê todas as releases');
select is((select build from app_releases where platform = 'android' order by build desc limit 1), 3,
  'a mais nova de uma plataforma sai ordenando por build');
select throws_ok(
  $$ insert into app_releases (platform, version, build, storage_path, sha256, size_bytes)
     values ('android', '9.9.9', 99, 'android/99/x.apk', repeat('f', 64), 1) $$,
  '42501', null, 'autenticado não insere release');
select throws_ok($$ update app_releases set notes = 'invadido' $$, '42501', null, 'autenticado não atualiza release');
select throws_ok($$ delete from app_releases $$, '42501', null, 'autenticado não apaga release');

-- Storage: autenticado lê o bucket, mas não escreve
reset role;
insert into storage.objects (bucket_id, name) values ('app-releases', 'android/3/organizacional.apk');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select is((select count(*) from storage.objects where bucket_id = 'app-releases')::int, 1,
  'autenticado enxerga os arquivos do bucket (para gerar a URL assinada)');
select throws_ok(
  $$ insert into storage.objects (bucket_id, name) values ('app-releases', 'android/4/malicioso.apk') $$,
  '42501', null, 'autenticado não envia arquivo ao bucket');
select set_config('storage.allow_delete_query', 'true', true);
delete from storage.objects where bucket_id = 'app-releases';
select is((select count(*) from storage.objects where bucket_id = 'app-releases')::int, 1,
  'autenticado não apaga arquivo do bucket');
update storage.objects set name = 'android/3/trocado.apk' where bucket_id = 'app-releases';
select is((select count(*) from storage.objects where name = 'android/3/trocado.apk')::int, 0,
  'autenticado não renomeia/substitui arquivo do bucket');

-- anon: nada
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select throws_ok($$ select * from app_releases $$, '42501', null, 'anon não lê a tabela de releases');
select is((select count(*) from storage.objects where bucket_id = 'app-releases')::int, 0, 'anon não lê o bucket');

select * from finish();
rollback;
