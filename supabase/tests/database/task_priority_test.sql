begin;
create extension if not exists pgtap with schema extensions;
select plan(6);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

insert into tasks (id, title) values ('aaaaaaaa-0000-0000-0000-000000000001', 'Sem prioridade');

select is(
  (select priority from tasks where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'media', 'por padrão a prioridade é média');

select lives_ok(
  $$ update tasks set priority = 'alta' where id = 'aaaaaaaa-0000-0000-0000-000000000001';
     update tasks set priority = 'baixa' where id = 'aaaaaaaa-0000-0000-0000-000000000001';
     update tasks set priority = 'media' where id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  'baixa, média e alta são aceitas');

select lives_ok(
  $$ insert into tasks (title, priority) values ('Urgente', 'alta') $$,
  'criar já com prioridade alta funciona');

select throws_ok(
  $$ update tasks set priority = 'urgente' where id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  '23514', null, 'prioridade desconhecida é rejeitada');

select throws_ok(
  $$ update tasks set priority = null where id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  '23502', null, 'prioridade não aceita nulo');

select throws_ok(
  $$ insert into tasks (title, priority) values ('Ruim', 'ALTA') $$,
  '23514', null, 'a prioridade diferencia maiúsculas');

select * from finish();
rollback;
