begin;
create extension if not exists pgtap with schema extensions;
select plan(4);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

-- O horário do servidor sempre vence: o celular não consegue envelhecer nem adiantar a localização.
insert into user_locations (lat, lon, accuracy_m, reported_at) values (-19.93, -43.94, 10, '2020-01-01T00:00:00Z');
select is(
  (select reported_at from user_locations), now(),
  'insert com reported_at de 2020 termina com now()');

update user_locations set reported_at = '2020-01-01T00:00:00Z';
select is(
  (select reported_at from user_locations), now(),
  'update com reported_at de 2020 termina com now()');

update user_locations set reported_at = now() + interval '1 day';
select is(
  (select reported_at from user_locations), now(),
  'update com reported_at no futuro termina com now()');

update user_locations set lat = -19.94;
select is(
  (select reported_at from user_locations), now(),
  'update sem tocar em reported_at também mantém now()');

select * from finish();
rollback;
