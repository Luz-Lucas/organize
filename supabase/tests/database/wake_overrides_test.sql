begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.dev');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

insert into wake_plans (id, label, days, time, echo_device_id)
  values ('aaaaaaaa-0000-0000-0000-000000000001', 'Aula cedo', '{1,2,3,4,5}', '07:00', 'ECHO1');

select lives_ok(
  $$ insert into wake_overrides (plan_id, run_date, skip) values ('aaaaaaaa-0000-0000-0000-000000000001', '2026-10-13', true) $$,
  'A pula o despertar de um dia');
select lives_ok(
  $$ insert into wake_overrides (plan_id, run_date, time) values ('aaaaaaaa-0000-0000-0000-000000000001', '2026-10-14', '06:30') $$,
  'A muda o horário de um dia');
select is(
  (select user_id::text from wake_overrides where run_date = '2026-10-14'),
  '11111111-1111-1111-1111-111111111111', 'user_id nasce do usuário logado');
select throws_ok(
  $$ insert into wake_overrides (plan_id, run_date, skip, time) values ('aaaaaaaa-0000-0000-0000-000000000001', '2026-10-15', false, null) $$,
  '23514', null, 'sem pular e sem horário é rejeitado');
select throws_ok(
  $$ insert into wake_overrides (plan_id, run_date, time) values ('aaaaaaaa-0000-0000-0000-000000000001', '2026-10-14', '08:00') $$,
  '23505', null, 'só uma exceção por plano e data');
select lives_ok(
  $$ update wake_overrides set skip = false, time = '07:15' where run_date = '2026-10-13' $$,
  'A edita a própria exceção');
select throws_ok(
  $$ update wake_overrides set skip = false, time = null where run_date = '2026-10-13' $$,
  '23514', null, 'edição que deixa a exceção vazia é rejeitada');
select lives_ok(
  $$ insert into wake_overrides (plan_id, run_date, time) values ('aaaaaaaa-0000-0000-0000-000000000001', '2026-10-16', '05:00') $$,
  'horário num dia fora de days também é aceito');

select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
select is((select count(*) from wake_overrides)::int, 0, 'B não vê as exceções de A');
select throws_ok(
  $$ insert into wake_overrides (plan_id, run_date, skip) values ('aaaaaaaa-0000-0000-0000-000000000001', '2026-10-20', true) $$,
  '42501', null, 'B não consegue apontar o despertar de A');
select lives_ok(
  $$ update wake_overrides set skip = true where plan_id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  'B atualiza zero linhas das exceções de A (sem erro, sem efeito)');
select lives_ok(
  $$ delete from wake_overrides where plan_id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  'B apaga zero linhas das exceções de A');

reset role;
select is((select count(*) from wake_overrides where plan_id = 'aaaaaaaa-0000-0000-0000-000000000001')::int, 3, 'as exceções de A continuam intactas');

delete from wake_plans where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select is((select count(*) from wake_overrides where plan_id = 'aaaaaaaa-0000-0000-0000-000000000001')::int, 0, 'apagar o despertar apaga suas exceções (cascata)');

select * from finish();
rollback;
