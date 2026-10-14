begin;
create extension if not exists pgtap with schema extensions;
select plan(19);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.dev');

-- Fixtures (papel postgres, ignora RLS)
insert into notes (id, user_id, title) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'Nota de A');
insert into imported_files (user_id, sha256, name, size_bytes) values
  ('11111111-1111-1111-1111-111111111111', repeat('a', 64), 'aula.pdf', 100),
  ('22222222-2222-2222-2222-222222222222', repeat('b', 64), 'outro.pdf', 200);

-- Usuário A (autenticado)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select is((select count(*) from imported_files)::int, 1, 'A vê só os próprios arquivos importados');
select is((select name from imported_files), 'aula.pdf', 'A lê o próprio registro');

select lives_ok(
  $$ insert into imported_files (sha256, name, size_bytes) values (repeat('c', 64), 'novo.pdf', 5) $$,
  'A insere (user_id vem de auth.uid())');
select is((select source from imported_files where sha256 = repeat('c', 64)), 'samsung_notes',
  'source tem default samsung_notes');
select is((select user_id from imported_files where sha256 = repeat('c', 64)), '11111111-1111-1111-1111-111111111111'::uuid,
  'user_id default = auth.uid()');
select lives_ok(
  $$ update imported_files set drive_file_id = 'drv1', device = 'tablet',
     note_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' where sha256 = repeat('c', 64) $$,
  'A atualiza drive_file_id, device e note_id');
select throws_ok($$ delete from imported_files $$, '42501', null, 'cliente não apaga registros');
select throws_ok(
  $$ insert into imported_files (user_id, sha256, name, size_bytes)
     values ('22222222-2222-2222-2222-222222222222', repeat('d', 64), 'x.pdf', 1) $$,
  '42501', null, 'A não grava em nome de B');
select throws_ok(
  $$ insert into imported_files (sha256, name, size_bytes) values (repeat('a', 64), 'dup.pdf', 1) $$,
  '23505', null, 'PK (user_id, sha256) impede duplicata do mesmo conteúdo');

-- Usuário B só enxerga e mexe no dele
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
select is((select count(*) from imported_files where user_id = '11111111-1111-1111-1111-111111111111')::int, 0,
  'B não lê os registros de A');
update imported_files set name = 'invadido' where sha256 = repeat('a', 64);
select is((select count(*) from imported_files where name = 'invadido')::int, 0, 'B não altera registros de A');
select lives_ok(
  $$ insert into imported_files (sha256, name, size_bytes) values (repeat('a', 64), 'mesmo-conteudo.pdf', 1) $$,
  'o mesmo sha256 em outro usuário é aceito (dedup é por usuário)');

-- Anônimo não lê nada
reset role;
set local role anon;
select throws_ok($$ select * from imported_files $$, '42501', null, 'anon não lê imported_files');

-- Constraints (papel postgres)
reset role;
select throws_ok(
  $$ insert into imported_files (user_id, sha256, name, size_bytes)
     values ('11111111-1111-1111-1111-111111111111', 'ABC', 'x', 1) $$,
  '23514', null, 'sha256 precisa ter 64 hex minúsculos');
select throws_ok(
  $$ insert into imported_files (user_id, sha256, name, size_bytes)
     values ('11111111-1111-1111-1111-111111111111', repeat('A', 64), 'x', 1) $$,
  '23514', null, 'sha256 em maiúsculas é rejeitado');
select throws_ok(
  $$ insert into imported_files (user_id, sha256, name, size_bytes)
     values ('11111111-1111-1111-1111-111111111111', repeat('e', 64), 'x', -1) $$,
  '23514', null, 'size_bytes não pode ser negativo');
select throws_ok(
  $$ insert into imported_files (user_id, sha256, name, size_bytes, source)
     values ('11111111-1111-1111-1111-111111111111', repeat('e', 64), 'x', 1, 'outra') $$,
  '23514', null, 'source desconhecido é rejeitado');

-- apagar a nota só solta o vínculo; apagar o usuário leva os registros
delete from notes where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
select is((select note_id from imported_files where sha256 = repeat('c', 64)), null,
  'apagar a nota zera note_id (on delete set null)');
delete from auth.users where id = '22222222-2222-2222-2222-222222222222';
select is((select count(*) from imported_files where user_id = '22222222-2222-2222-2222-222222222222')::int, 0,
  'apagar o usuário apaga os registros (cascade)');

select * from finish();
rollback;
