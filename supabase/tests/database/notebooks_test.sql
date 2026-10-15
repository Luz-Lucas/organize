begin;
create extension if not exists pgtap with schema extensions;
select plan(36);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.dev');

-- Fixtures (papel postgres, ignora RLS)
insert into notes (id, user_id, title, kind) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'Caderno de A', 'notebook'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '22222222-2222-2222-2222-222222222222', 'Caderno de B', 'notebook'),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', '11111111-1111-1111-1111-111111111111', 'Nota de texto de A', 'text');
insert into note_pages (id, user_id, note_id, idx, recognized_text) values
  ('a0000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 0, 'olá mundo'),
  ('b0000000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 0, 'segredo de B');

-- Estrutura e padrões
select is((select kind from notes where id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'), 'text', 'kind explícito text');
insert into notes (id, user_id, title) values
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', '11111111-1111-1111-1111-111111111111', 'Sem kind');
select is((select kind from notes where id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'), 'text', 'kind padrão é text');
select throws_ok(
  $$ insert into notes (user_id, title, kind) values ('11111111-1111-1111-1111-111111111111', 'Inválida', 'planilha') $$,
  '23514', null, 'kind inválido é rejeitado');
select is((select background from note_pages where id = 'a0000000-0000-0000-0000-000000000001'), 'lined', 'background padrão é lined');
select is((select version from note_pages where id = 'a0000000-0000-0000-0000-000000000001'), 0, 'version padrão é 0');
select is((select data from note_pages where id = 'a0000000-0000-0000-0000-000000000001'), '', 'data padrão é vazio');

-- Constraints (papel postgres)
select throws_ok(
  $$ insert into note_pages (user_id, note_id, idx, background) values
     ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 5, 'xadrez') $$,
  '23514', null, 'background inválido é rejeitado');
select throws_ok(
  $$ insert into note_pages (user_id, note_id, idx) values
     ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', -1) $$,
  '23514', null, 'idx negativo é rejeitado');
select lives_ok(
  $$ insert into note_pages (user_id, note_id, idx, data) values
     ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 1, repeat('x', 4000000)) $$,
  'data com exatamente 4.000.000 de bytes é aceito');
select throws_ok(
  $$ insert into note_pages (user_id, note_id, idx, data) values
     ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 2, repeat('x', 4000001)) $$,
  '23514', null, 'data acima de 4.000.000 de bytes é rejeitado');
select throws_ok(
  $$ update note_pages set data = repeat('é', 2000001) where id = 'a0000000-0000-0000-0000-000000000001' $$,
  '23514', null, 'o limite conta bytes (octet_length), não caracteres');
-- A unicidade (note_id, idx) é adiada; força a checagem imediata para provar que ela existe
delete from note_pages where note_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' and idx = 1;
set constraints note_pages_note_idx_uq immediate;
select throws_ok(
  $$ insert into note_pages (user_id, note_id, idx) values
     ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 0) $$,
  '23505', null, 'unique (note_id, idx) impede página repetida');
set constraints note_pages_note_idx_uq deferred;

-- Adiada de fábrica: trocar idx entre duas páginas na mesma transação funciona
insert into note_pages (id, user_id, note_id, idx) values
  ('a0000000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 1);
select lives_ok(
  $$ update note_pages set idx = 1 - idx where note_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' $$,
  'reordenar (trocar idx) funciona porque a unicidade é adiada');
select is((select idx from note_pages where id = 'a0000000-0000-0000-0000-000000000001'), 1,
  'a troca de idx foi aplicada');
delete from note_pages where id = 'a0000000-0000-0000-0000-000000000002';
update note_pages set idx = 0 where id = 'a0000000-0000-0000-0000-000000000001';

-- Realtime
select ok(exists (select 1 from pg_publication_tables
  where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'note_pages'),
  'note_pages está na publicação realtime');

-- Usuário A (autenticado)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select is((select count(*) from note_pages)::int, 1, 'A vê só as próprias páginas');
select lives_ok(
  $$ insert into note_pages (note_id, idx) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 1) $$,
  'A cria página no próprio caderno (user_id vem de auth.uid())');
select is((select user_id from note_pages where idx = 1), '11111111-1111-1111-1111-111111111111'::uuid,
  'user_id default = auth.uid()');
select lives_ok(
  $$ update note_pages set data = 'abc', version = 1 where idx = 1 $$, 'A atualiza a própria página');
select isnt((select updated_at from note_pages where idx = 1), null, 'updated_at preenchido');
select throws_ok(
  $$ insert into note_pages (user_id, note_id, idx) values
     ('22222222-2222-2222-2222-222222222222', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 1) $$,
  '42501', null, 'A não grava página em nome de B');
select throws_ok(
  $$ insert into note_pages (note_id, idx) values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 7) $$,
  '42501', null, 'A não grava página no caderno de B (nota alheia)');
select lives_ok($$ delete from note_pages where idx = 1 $$, 'A apaga a própria página');

-- Usuário B não enxerga nem mexe nas páginas de A
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
select is((select count(*) from note_pages where note_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')::int, 0,
  'B não lê páginas de A');
update note_pages set recognized_text = 'invadido' where id = 'a0000000-0000-0000-0000-000000000001';
delete from note_pages where id = 'a0000000-0000-0000-0000-000000000001';
reset role;
select is((select recognized_text from note_pages where id = 'a0000000-0000-0000-0000-000000000001'), 'olá mundo',
  'B não altera nem apaga páginas de A');

-- Anônimo não lê nada
set local role anon;
select throws_ok($$ select * from note_pages $$, '42501', null, 'anon não lê note_pages');
reset role;

-- Cascata: apagar a nota leva as páginas; apagar o usuário também
delete from notes where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
select is((select count(*) from note_pages where note_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')::int, 0,
  'apagar a nota apaga as páginas (cascade)');

-- Storage: bucket e policies do dono por prefixo <user_id>/
select is((select public from storage.buckets where id = 'notebook-images'), false, 'bucket notebook-images é privado');
select is((select file_size_limit from storage.buckets where id = 'notebook-images'), 10485760::bigint,
  'bucket limita imagens a 10 MB');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
select lives_ok(
  $$ insert into storage.objects (bucket_id, name, owner_id) values
     ('notebook-images', '11111111-1111-1111-1111-111111111111/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/img1.png',
      '11111111-1111-1111-1111-111111111111') $$,
  'A envia imagem para o próprio prefixo');
select throws_ok(
  $$ insert into storage.objects (bucket_id, name) values
     ('notebook-images', '22222222-2222-2222-2222-222222222222/x/img.png') $$,
  '42501', null, 'A não envia imagem para o prefixo de B');
select throws_ok(
  $$ insert into storage.objects (bucket_id, name) values
     ('notebook-images', 'img-solta.png') $$,
  '42501', null, 'A não envia imagem fora de uma pasta de usuário');
select is((select count(*) from storage.objects where bucket_id = 'notebook-images')::int, 1, 'A lê a própria imagem');

select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
select is((select count(*) from storage.objects where bucket_id = 'notebook-images')::int, 0, 'B não lê imagens de A');
-- o gatilho protect_delete bloqueia DELETE direto; libera para exercitar só a policy
select set_config('storage.allow_delete_query', 'true', true);
delete from storage.objects where bucket_id = 'notebook-images';
reset role;
select is((select count(*) from storage.objects where bucket_id = 'notebook-images')::int, 1, 'B não apaga imagens de A');

set local role anon;
select is((select count(*) from storage.objects where bucket_id = 'notebook-images')::int, 0, 'anon não lê imagens do caderno');
reset role;

select * from finish();
rollback;
