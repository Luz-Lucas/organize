begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.dev');

-- Fixtures (papel postgres, ignora RLS)
insert into google_accounts (user_id, provider, account_email, refresh_token_enc, scopes) values
  ('11111111-1111-1111-1111-111111111111', 'gmail', 'a@gmail.test', 'cifrado', 'gmail.metadata'),
  ('11111111-1111-1111-1111-111111111111', 'drive', 'a@gmail.test', 'cifrado2', 'https://www.googleapis.com/auth/drive');
insert into drive_state (user_id, account_email, status, root_folder_id) values
  ('11111111-1111-1111-1111-111111111111', 'a@gmail.test', 'ok', 'pasta-a'),
  ('22222222-2222-2222-2222-222222222222', 'b@gmail.test', 'ok', 'pasta-b');

select is((select count(*) from google_accounts where user_id = '11111111-1111-1111-1111-111111111111')::int, 2,
  'o mesmo usuário pode ter gmail e drive (chave user_id+provider)');

-- Usuário A (autenticado)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select throws_ok($$ select * from google_accounts $$, '42501', null,
  'cliente não lê google_accounts (nem o token do drive)');
select is((select count(*) from drive_state)::int, 1, 'A vê só o próprio drive_state');
select is((select root_folder_id from drive_state), 'pasta-a', 'A lê a pasta raiz do próprio estado');
select throws_ok(
  $$ insert into drive_state (user_id, status) values ('11111111-1111-1111-1111-111111111111', 'ok') $$,
  '42501', null, 'cliente não escreve em drive_state');
select throws_ok($$ update drive_state set root_folder_id = 'invadida' $$, '42501', null,
  'cliente não altera drive_state');
select throws_ok($$ delete from drive_state $$, '42501', null, 'cliente não apaga drive_state');

-- Usuário B só enxerga o dele
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
select is((select count(*) from drive_state where user_id = '11111111-1111-1111-1111-111111111111')::int, 0,
  'B não vê o estado de A');

-- Anônimo não lê nada
reset role;
set local role anon;
select throws_ok($$ select * from drive_state $$, '42501', null, 'anon não lê drive_state');

-- Constraints (papel postgres)
reset role;
select throws_ok(
  $$ insert into drive_state (user_id, status) values ('22222222-2222-2222-2222-222222222222', 'ok') $$,
  '23505', null, 'PK: um estado por usuário');
select throws_ok(
  $$ update drive_state set status = 'qualquer' where user_id = '22222222-2222-2222-2222-222222222222' $$,
  '23514', null, 'status inválido é rejeitado');
select throws_ok(
  $$ insert into google_accounts (user_id, provider, account_email, refresh_token_enc, scopes)
     values ('22222222-2222-2222-2222-222222222222', 'outlook', 'b@x.test', 'x', 'y') $$,
  '23514', null, 'provider desconhecido continua rejeitado');
select lives_ok(
  $$ insert into google_accounts (user_id, provider, account_email, refresh_token_enc, scopes)
     values ('22222222-2222-2222-2222-222222222222', 'drive', 'b@x.test', 'x', 'y') $$,
  'provider drive é aceito');
select is((select status from drive_state where user_id = '22222222-2222-2222-2222-222222222222'), 'ok',
  'default/valores do estado preservados');

select * from finish();
rollback;
