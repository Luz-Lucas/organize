begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.dev');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select lives_ok(
  $$ insert into wake_plans (id, label, days, time, echo_device_id)
     values ('aaaaaaaa-0000-0000-0000-000000000001', 'Aula cedo', '{1,2,3,4,5}', '07:00', 'ECHO1') $$,
  'A cria um despertar');
select throws_ok(
  $$ insert into wake_plans (label, days, time, echo_device_id) values ('x', '{}', '07:00', 'E') $$,
  '23514', null, 'despertar sem dias é rejeitado');
select throws_ok(
  $$ insert into wake_plans (label, days, time, echo_device_id) values ('x', '{0,8}', '07:00', 'E') $$,
  '23514', null, 'dias fora de 1..7 são rejeitados');
select lives_ok(
  $$ insert into alexa_commands (kind, payload) values ('speak', '{"text":"oi","echoDeviceId":"ECHO1"}') $$,
  'A enfileira um comando');
select throws_ok(
  $$ insert into alexa_commands (kind, payload, status) values ('speak', '{}', 'done') $$,
  '42501', null, 'app não insere comando já concluído');

select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
select is((select count(*) from wake_plans)::int, 0, 'B não vê os despertares de A');

-- A ponte usa a service role (aqui: postgres, que ignora RLS)
reset role;
select ok(
  claim_wake_run('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000001', '2026-09-28', now()),
  'primeira reivindicação do despertar vence');
select ok(
  not claim_wake_run('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000001', '2026-09-28', now()),
  'segunda reivindicação no mesmo dia não dispara de novo');
select ok(claim_command('11111111-1111-1111-1111-111111111111', (select id from alexa_commands limit 1)), 'primeira reivindicação do comando vence');
select ok(not claim_command('11111111-1111-1111-1111-111111111111', (select id from alexa_commands limit 1)), 'comando não roda duas vezes');

select * from finish();
rollback;
