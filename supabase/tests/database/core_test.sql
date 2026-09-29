begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.dev');

-- Usuário A
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select lives_ok(
  $$ insert into spaces (id, name, kind) values ('aaaaaaaa-0000-0000-0000-000000000001', 'Cálculo I', 'materia') $$,
  'A cria um espaço');
select is(
  (select user_id from spaces where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'user_id vem de auth.uid()');
select lives_ok(
  $$ insert into notes (id, space_id, title) values ('aaaaaaaa-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', 'Limites') $$,
  'A cria uma nota');
select throws_ok(
  $$ insert into notes (space_id, title) values ('aaaaaaaa-0000-0000-0000-000000000001', '  limites ') $$,
  '23505', null,
  'título duplicado (ignorando caixa e espaços) é rejeitado');

insert into tasks (space_id, title) values ('aaaaaaaa-0000-0000-0000-000000000001', 'Lista 1');
insert into events (space_id, title, starts_at, ends_at)
  values ('aaaaaaaa-0000-0000-0000-000000000001', 'Aula', now(), now() + interval '1 hour');

-- Usuário B
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
select is((select count(*) from spaces)::int, 0, 'B não vê os espaços de A');
select throws_ok(
  $$ insert into spaces (user_id, name) values ('11111111-1111-1111-1111-111111111111', 'invasão') $$,
  '42501', null,
  'B não cria linhas em nome de A');

-- De volta a A: excluir o espaço
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
delete from spaces where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select is(
  (select count(*) from notes)::int + (select count(*) from tasks)::int, 0,
  'notas e tarefas somem junto com o espaço');
select is(
  (select count(*) from events where space_id is null)::int, 1,
  'o evento continua na agenda, sem espaço');

select * from finish();
rollback;
