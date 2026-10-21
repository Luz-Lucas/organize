begin;
create extension if not exists pgtap with schema extensions;
select plan(28);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.dev');

-- padrões nas linhas novas (e, pelo default da coluna, nas que já existiam)
insert into tasks (id, user_id, title) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Tarefa');
insert into events (id, user_id, title, starts_at, ends_at) values
  ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Evento', now(), now() + interval '1 hour');
insert into user_settings (user_id) values ('11111111-1111-1111-1111-111111111111');

select is((select reminders from tasks where title = 'Tarefa'), '{60}'::smallint[], 'tarefa avisa 1 hora antes por padrão');
select is((select reminders from events where title = 'Evento'), '{30}'::smallint[], 'evento avisa 30 min antes por padrão');

-- check de valores e de repetidos
select lives_ok($$ update tasks set reminders = '{1440,60,30,15}' where title = 'Tarefa' $$, 'tarefa aceita as 4 opções');
select lives_ok($$ update tasks set reminders = '{}' where title = 'Tarefa' $$, 'tarefa aceita nenhum lembrete');
select throws_ok($$ update tasks set reminders = '{45}' where title = 'Tarefa' $$, '23514', null, 'tarefa recusa valor fora das opções');
select throws_ok($$ update tasks set reminders = '{60,60}' where title = 'Tarefa' $$, '23514', null, 'tarefa recusa valor repetido');
select throws_ok($$ update tasks set reminders = null where title = 'Tarefa' $$, '23502', null, 'tarefa recusa reminders nulo');
select throws_ok($$ update tasks set reminders = '{60,null}' where title = 'Tarefa' $$, '23514', null, 'tarefa recusa elemento nulo');
select lives_ok($$ update events set reminders = '{1440,15}' where title = 'Evento' $$, 'evento aceita várias opções');
select throws_ok($$ update events set reminders = '{0}' where title = 'Evento' $$, '23514', null, 'evento recusa valor fora das opções');
select throws_ok($$ update events set reminders = '{30,15,30}' where title = 'Evento' $$, '23514', null, 'evento recusa valor repetido');

-- ajustes
select is((select reminders_phone from user_settings where user_id = '11111111-1111-1111-1111-111111111111'), true, 'lembretes no celular ligados por padrão');
select is((select reminders_alexa from user_settings where user_id = '11111111-1111-1111-1111-111111111111'), true, 'lembretes na Alexa ligados por padrão');
select is((select reminder_echo from user_settings where user_id = '11111111-1111-1111-1111-111111111111'), null, 'sem Echo escolhido por padrão');
select is((select dnd_enabled from user_settings where user_id = '11111111-1111-1111-1111-111111111111'), true, 'não perturbe ligado por padrão');
select is((select dnd_start from user_settings where user_id = '11111111-1111-1111-1111-111111111111'), '23:00'::time, 'não perturbe começa às 23:00');
select is((select dnd_end from user_settings where user_id = '11111111-1111-1111-1111-111111111111'), '10:00'::time, 'não perturbe termina às 10:00');

-- reminder_deliveries: dono lê, só o service role escreve, único por disparo
select has_table('public', 'reminder_deliveries', 'existe reminder_deliveries');
insert into reminder_deliveries (user_id, kind, item_id, fire_at, channel) values
  ('11111111-1111-1111-1111-111111111111', 'event', 'bbbbbbbb-0000-0000-0000-000000000001', '2026-10-22 17:30+00', 'alexa');

select throws_ok(
  $$ insert into reminder_deliveries (user_id, kind, item_id, fire_at, channel)
     values ('11111111-1111-1111-1111-111111111111', 'event', 'bbbbbbbb-0000-0000-0000-000000000001', '2026-10-22 17:30+00', 'alexa') $$,
  '23505', null, 'o mesmo disparo não entra duas vezes');
select throws_ok(
  $$ insert into reminder_deliveries (user_id, kind, item_id, fire_at, channel)
     values ('11111111-1111-1111-1111-111111111111', 'nota', gen_random_uuid(), now(), 'alexa') $$,
  '23514', null, 'kind só aceita task ou event');
select throws_ok(
  $$ insert into reminder_deliveries (user_id, kind, item_id, fire_at, channel)
     values ('11111111-1111-1111-1111-111111111111', 'task', gen_random_uuid(), now(), 'push') $$,
  '23514', null, 'channel só aceita alexa');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
select is((select count(*) from reminder_deliveries)::int, 1, 'A lê os próprios disparos');
select throws_ok(
  $$ insert into reminder_deliveries (user_id, kind, item_id, fire_at, channel)
     values ('11111111-1111-1111-1111-111111111111', 'task', gen_random_uuid(), now(), 'alexa') $$,
  '42501', null, 'o usuário logado não escreve em reminder_deliveries');
select lives_ok($$ update user_settings set dnd_start = '22:00', reminder_echo = 'ECHO1' $$, 'A edita os próprios ajustes');
select is((select dnd_start from user_settings where user_id = '11111111-1111-1111-1111-111111111111'), '22:00'::time, 'A grava o novo início do não perturbe');

select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
select is((select count(*) from reminder_deliveries)::int, 0, 'B não vê os disparos de A');
select lives_ok($$ delete from reminder_deliveries $$, 'B apaga zero linhas (sem erro)');

reset role;
select is((select count(*) from reminder_deliveries where user_id = '11111111-1111-1111-1111-111111111111')::int, 1, 'o disparo de A continua intacto');

select * from finish();
rollback;
