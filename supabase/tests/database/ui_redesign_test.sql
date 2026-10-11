begin;
create extension if not exists pgtap with schema extensions;
select plan(6);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.dev');

-- Usuário A
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

insert into notices (id, title) values ('aaaaaaaa-0000-0000-0000-0000000000a1', 'Prova sexta');
insert into user_settings (theme) values ('coral');

select throws_ok(
  $$ insert into user_settings (user_id, theme) values ('11111111-1111-1111-1111-111111111111', 'lunar') $$,
  '23505', null, 'só existe uma linha de configurações por usuário');
select lives_ok(
  $$ insert into alexa_commands (kind) values ('delete_device') $$,
  'comando delete_device é aceito');

-- Usuário B
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
select is((select count(*) from notices)::int, 0, 'B não vê os avisos de A');
select is((select count(*) from user_settings)::int, 0, 'B não vê as configurações de A');
update notices set title = 'invadido' where id = 'aaaaaaaa-0000-0000-0000-0000000000a1';

-- Tema inválido (B, linha própria)
select throws_ok(
  $$ insert into user_settings (theme) values ('neon') $$,
  '23514', null, 'tema desconhecido é rejeitado');

-- De volta a A
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
select is(
  (select title from notices where id = 'aaaaaaaa-0000-0000-0000-0000000000a1'),
  'Prova sexta', 'B não altera o aviso de A');

select * from finish();
rollback;
