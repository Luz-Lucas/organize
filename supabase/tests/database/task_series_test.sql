begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev');

select has_column('public', 'tasks', 'series_id', 'tasks tem series_id');
select has_column('public', 'tasks', 'recurrence', 'tasks tem recurrence');
select has_index('public', 'tasks', 'tasks_series_idx', 'índice (user_id, series_id, due_at)');

select lives_ok(
  $$ insert into tasks (user_id, title) values ('11111111-1111-1111-1111-111111111111', 'Avulsa') $$,
  'tarefa sem série continua válida');
select is(
  (select series_id from tasks where title = 'Avulsa'), null, 'tarefa avulsa fica sem série');

select throws_ok(
  $$ insert into tasks (user_id, title, recurrence)
     values ('11111111-1111-1111-1111-111111111111', 'Ruim', '[1,2]'::jsonb) $$,
  '23514', null, 'recurrence precisa ser um objeto jsonb');
select lives_ok(
  $$ insert into tasks (user_id, title, due_at, series_id, recurrence)
     values ('11111111-1111-1111-1111-111111111111', 'Lab', now(), gen_random_uuid(),
             '{"freq":"weekly","days":[2],"until":"2026-12-01","count":null}'::jsonb) $$,
  'recurrence objeto é aceito');

select * from finish();
rollback;
