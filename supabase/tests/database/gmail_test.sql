begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.dev');

-- Fixtures (papel postgres, ignora RLS)
insert into google_accounts (user_id, provider, account_email, refresh_token_enc, scopes) values
  ('11111111-1111-1111-1111-111111111111', 'gmail', 'a@gmail.test', 'cifrado', 'https://www.googleapis.com/auth/gmail.metadata');
insert into email_state (user_id, account_email, unread_count, status) values
  ('11111111-1111-1111-1111-111111111111', 'a@gmail.test', 3, 'ok'),
  ('22222222-2222-2222-2222-222222222222', 'b@gmail.test', 9, 'ok');
insert into email_items (user_id, gmail_id, from_addr, subject, unread) values
  ('11111111-1111-1111-1111-111111111111', 'm1', 'x@x.test', 'Um', true),
  ('11111111-1111-1111-1111-111111111111', 'm2', 'y@y.test', 'Dois', false),
  ('22222222-2222-2222-2222-222222222222', 'm3', 'z@z.test', 'Três', true);

-- Usuário A (autenticado)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select throws_ok($$ select * from google_accounts $$, '42501', null,
  'cliente não lê google_accounts');
select throws_ok(
  $$ insert into google_accounts (user_id, provider, account_email, refresh_token_enc, scopes)
     values ('11111111-1111-1111-1111-111111111111', 'gmail', 'a@gmail.test', 'x', 'y') $$,
  '42501', null, 'cliente não insere em google_accounts');
select throws_ok($$ update google_accounts set refresh_token_enc = 'x' $$, '42501', null,
  'cliente não altera google_accounts');

select is((select count(*) from email_state)::int, 1, 'A vê só o próprio email_state');
select is((select unread_count from email_state), 3, 'A lê a contagem do próprio estado');
select is((select count(*) from email_items)::int, 2, 'A vê só os próprios email_items');

select throws_ok(
  $$ insert into email_state (user_id, status) values ('11111111-1111-1111-1111-111111111111', 'ok') $$,
  '42501', null, 'cliente não escreve em email_state');
select throws_ok($$ update email_items set subject = 'invadido' $$, '42501', null,
  'cliente não altera email_items');

-- Usuário B só enxerga os dele
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
select is((select count(*) from email_items where user_id = '11111111-1111-1111-1111-111111111111')::int, 0,
  'B não vê os itens de A');
select is((select count(*) from email_state where user_id = '11111111-1111-1111-1111-111111111111')::int, 0,
  'B não vê o estado de A');

-- Anônimo não lê nada
reset role;
set local role anon;
select throws_ok($$ select * from email_state $$, '42501', null, 'anon não lê email_state');

-- Constraints (papel postgres)
reset role;
select throws_ok(
  $$ insert into email_state (user_id, status) values ('22222222-2222-2222-2222-222222222222', 'ok') $$,
  '23505', null, 'PK: um estado por usuário');
select throws_ok(
  $$ update email_state set status = 'qualquer' where user_id = '22222222-2222-2222-2222-222222222222' $$,
  '23514', null, 'status inválido é rejeitado');
select throws_ok(
  $$ update email_state set unread_count = -1 where user_id = '22222222-2222-2222-2222-222222222222' $$,
  '23514', null, 'contagem negativa é rejeitada');
select throws_ok(
  $$ insert into google_accounts (user_id, provider, account_email, refresh_token_enc, scopes)
     values ('22222222-2222-2222-2222-222222222222', 'outlook', 'b@x.test', 'x', 'y') $$,
  '23514', null, 'provider desconhecido é rejeitado');

select * from finish();
rollback;
