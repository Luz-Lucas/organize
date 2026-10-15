begin;
create extension if not exists pgtap with schema extensions;
select plan(31);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.dev');

-- Usuário A
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

insert into wake_plans (id, label, days, time, echo_device_id)
  values ('aaaaaaaa-0000-0000-0000-000000000001', 'Aula cedo', '{1,2,3,4,5}', '07:00', 'ECHO1');
insert into user_settings (theme) values ('coral');
insert into user_locations (lat, lon, accuracy_m) values (-19.93, -43.94, 12.5);

-- user_locations: checks
select is((select count(*) from user_locations)::int, 1, 'A grava a própria localização');
select throws_ok($$ update user_locations set lat = 91 $$, '23514', null, 'latitude acima de 90 é rejeitada');
select throws_ok($$ update user_locations set lat = -90.5 $$, '23514', null, 'latitude abaixo de -90 é rejeitada');
select throws_ok($$ update user_locations set lon = 181 $$, '23514', null, 'longitude acima de 180 é rejeitada');
select throws_ok($$ update user_locations set lon = -181 $$, '23514', null, 'longitude abaixo de -180 é rejeitada');
select throws_ok($$ update user_locations set accuracy_m = -1 $$, '23514', null, 'precisão negativa é rejeitada');
select lives_ok(
  $$ update user_locations set lat = 90, lon = -180, accuracy_m = 0;
     update user_locations set lat = -90, lon = 180, accuracy_m = null $$,
  'limites de coordenada, precisão zero e precisão nula são aceitos');
select throws_ok(
  $$ insert into user_locations (user_id, lat, lon) values ('11111111-1111-1111-1111-111111111111', 0, 0) $$,
  '23505', null, 'só existe uma localização por usuário');
select throws_ok(
  $$ insert into user_locations (user_id, lat, lon) values ('22222222-2222-2222-2222-222222222222', 0, 0) $$,
  '42501', null, 'A não grava localização em nome de B');

-- user_settings: casa
select is((select home_radius_m from user_settings), 50, 'raio padrão da casa é 50 m');
select is((select require_home from user_settings), true, 'por padrão exige estar em casa');
select is((select home_lat from user_settings), null, 'sem casa por padrão');
select throws_ok($$ update user_settings set home_lat = -19.93 $$, '23514', null, 'latitude sem longitude é rejeitada');
select throws_ok($$ update user_settings set home_lat = 91, home_lon = 0 $$, '23514', null, 'latitude da casa fora da faixa é rejeitada');
select throws_ok($$ update user_settings set home_lat = 0, home_lon = 181 $$, '23514', null, 'longitude da casa fora da faixa é rejeitada');
select throws_ok($$ update user_settings set home_radius_m = 19 $$, '23514', null, 'raio abaixo de 20 m é rejeitado');
select throws_ok($$ update user_settings set home_radius_m = 501 $$, '23514', null, 'raio acima de 500 m é rejeitado');
select lives_ok(
  $$ update user_settings set home_lat = -19.93, home_lon = -43.94, home_radius_m = 20;
     update user_settings set home_radius_m = 500, require_home = false;
     update user_settings set home_lat = null, home_lon = null $$,
  'casa válida, limites do raio e remoção da casa passam');

-- wake_plans
select is((select include_weather from wake_plans), true, 'por padrão fala o clima');
select is((select device_actions from wake_plans), '[]'::jsonb, 'por padrão não há ações de dispositivos');
select is((select phone_alarm from wake_plans), 'fallback', 'phone_alarm padrão é fallback');
select is((select briefing_delay_sec from wake_plans), null, 'espera em segundos é nula por padrão');
select throws_ok($$ update wake_plans set device_actions = '{}'::jsonb $$, '23514', null, 'device_actions que não é array é rejeitado');
select throws_ok($$ update wake_plans set phone_alarm = 'x' $$, '23514', null, 'phone_alarm desconhecido é rejeitado');
select throws_ok($$ update wake_plans set briefing_delay_sec = -1 $$, '23514', null, 'espera negativa é rejeitada');
select throws_ok($$ update wake_plans set briefing_delay_sec = 1801 $$, '23514', null, 'espera acima de 1800 s é rejeitada');
select lives_ok(
  $$ update wake_plans set briefing_delay_sec = 0;
     update wake_plans set briefing_delay_sec = 10;
     update wake_plans set briefing_delay_sec = 1800;
     update wake_plans set briefing_delay_sec = null $$,
  'esperas 0, 10, 1800 e nula são aceitas');
select lives_ok(
  $$ update wake_plans set include_weather = false, phone_alarm = 'never',
       device_actions = '[{"entityId":"luz1","name":"Luz","action":"turnOn","delayMin":0}]'::jsonb;
     update wake_plans set phone_alarm = 'always';
     update wake_plans set phone_alarm = 'fallback', device_actions = '[]'::jsonb $$,
  'valores válidos de clima, alarme e ações passam');

-- wake_runs: skipped (a linha é criada pela ponte, que usa a chave de serviço)
reset role;
insert into wake_runs (user_id, plan_id, run_date, planned_for, status)
  values ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000001', '2026-10-13', now(), 'skipped');
select is((select status from wake_runs where plan_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 'skipped', 'wake_runs aceita o status skipped');

-- Usuário B não vê nem mexe nos dados de A
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
select is((select count(*) from user_locations)::int, 0, 'B não lê a localização de A');
select is((select count(*) from user_locations where lat = -90)::int, 0, 'B não lê a localização de A (filtro)');

select * from finish();
rollback;
