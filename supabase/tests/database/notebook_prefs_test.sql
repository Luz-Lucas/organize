begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.dev');

-- Usuário A (linha própria de configurações)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
insert into user_settings (theme) values ('coral');

select is(
  (select notebook_prefs from user_settings),
  '{}'::jsonb,
  'notebook_prefs começa como objeto vazio');

update user_settings
  set notebook_prefs = '{"v":1,"pens":[{"tool":"pen","argb":4278190080,"width":3.0}],"colors":[4278190080],"compact":true}'::jsonb;
select is(
  (select notebook_prefs -> 'pens' -> 0 ->> 'tool' from user_settings),
  'pen',
  'favoritos do caderno são gravados e lidos');
select is(
  (select theme from user_settings),
  'coral',
  'gravar os favoritos não mexe nos outros ajustes');

select throws_ok(
  $$ update user_settings set notebook_prefs = '[]'::jsonb $$,
  '23514', null, 'notebook_prefs precisa ser um objeto (array é rejeitado)');
select throws_ok(
  $$ update user_settings set notebook_prefs = '"texto"'::jsonb $$,
  '23514', null, 'notebook_prefs precisa ser um objeto (texto é rejeitado)');
select throws_ok(
  $$ update user_settings set notebook_prefs = null $$,
  '23502', null, 'notebook_prefs não aceita nulo');

-- Usuário B não vê nem altera os favoritos de A
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
select is((select count(*) from user_settings)::int, 0, 'B não vê as configurações de A');
update user_settings set notebook_prefs = '{"v":1,"invadido":true}'::jsonb;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
select is(
  (select notebook_prefs ->> 'invadido' from user_settings),
  null,
  'B não altera os favoritos de A');

select * from finish();
rollback;
