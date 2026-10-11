begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

insert into wake_plans (id, label, days, time, echo_device_id)
  values ('aaaaaaaa-0000-0000-0000-000000000001', 'Aula cedo', '{1,2,3,4,5}', '07:00', 'ECHO1');

select is(
  (select music_stop_after_sec from wake_plans where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  null, 'por padrão a música não para (music_stop_after_sec nulo)');
select is(
  (select after_music from wake_plans where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'briefing', 'por padrão, depois da música vem o resumo');

select throws_ok(
  $$ update wake_plans set music_stop_after_sec = 3 where id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  '23514', null, 'parar após 3 s (menos de 5) é rejeitado');
select throws_ok(
  $$ update wake_plans set music_stop_after_sec = 700 where id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  '23514', null, 'parar após 700 s (mais de 600) é rejeitado');
select throws_ok(
  $$ update wake_plans set after_music = 'x' where id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  '23514', null, 'after_music desconhecido é rejeitado');
select throws_ok(
  $$ update wake_plans set after_music = null where id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  '23502', null, 'after_music não aceita nulo');
select lives_ok(
  $$ update wake_plans set music_stop_after_sec = 5 where id = 'aaaaaaaa-0000-0000-0000-000000000001';
     update wake_plans set music_stop_after_sec = 600 where id = 'aaaaaaaa-0000-0000-0000-000000000001';
     update wake_plans set music_stop_after_sec = null where id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  'os limites 5 e 600 e o nulo são aceitos');
select lives_ok(
  $$ update wake_plans set music_stop_after_sec = 30, after_music = 'headlines' where id = 'aaaaaaaa-0000-0000-0000-000000000001';
     update wake_plans set after_music = 'end' where id = 'aaaaaaaa-0000-0000-0000-000000000001';
     update wake_plans set after_music = 'briefing' where id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  'valores válidos de after_music passam');

select * from finish();
rollback;
