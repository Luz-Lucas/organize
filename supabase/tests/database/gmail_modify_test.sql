begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.dev');

-- Fixtures (papel postgres, ignora RLS): sem informar can_modify, vale o padrão.
insert into email_state (user_id, account_email, unread_count, status) values
  ('11111111-1111-1111-1111-111111111111', 'a@gmail.test', 3, 'ok');
insert into email_state (user_id, account_email, unread_count, status, can_modify) values
  ('22222222-2222-2222-2222-222222222222', 'b@gmail.test', 1, 'ok', true);

select has_column('public', 'email_state', 'can_modify', 'email_state tem can_modify');
select col_type_is('public', 'email_state', 'can_modify', 'boolean', 'can_modify é boolean');
select col_not_null('public', 'email_state', 'can_modify', 'can_modify é not null');
select is((select can_modify from email_state where user_id = '11111111-1111-1111-1111-111111111111'), false,
  'padrão: false (conta com o escopo antigo)');
select throws_ok(
  $$ update email_state set can_modify = null where user_id = '11111111-1111-1111-1111-111111111111' $$,
  '23502', null, 'can_modify não aceita null');

-- Usuário A (autenticado): lê o próprio valor, não escreve, não vê o de B
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select is((select can_modify from email_state), false, 'A lê o próprio can_modify');
select throws_ok($$ update email_state set can_modify = true $$, '42501', null,
  'cliente não altera can_modify');
select is((select count(*) from email_state where can_modify)::int, 0, 'A não enxerga o can_modify de B');

select * from finish();
rollback;
