begin;
create extension if not exists pgtap with schema extensions;
select plan(19);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.dev');

select has_column('public', 'events', 'series_id', 'events tem series_id');
select has_column('public', 'events', 'recurrence', 'events tem recurrence');
select has_index('public', 'events', 'events_series_idx', 'índice (user_id, series_id, starts_at)');

-- Eventos importados, ainda sem série (como antes da migração).
-- Horários em UTC: 13:00Z = 10:00 em São Paulo; 15:00Z = 12:00.
insert into events (user_id, title, starts_at, ends_at, source, external_id) values
  ('11111111-1111-1111-1111-111111111111', 'Reunião', '2026-10-12 13:00+00', '2026-10-12 14:00+00', 'google', 'abc_20261012T130000Z'),
  ('11111111-1111-1111-1111-111111111111', 'Reunião', '2026-10-19 13:00+00', '2026-10-19 14:00+00', 'google', 'abc_20261019T130000Z'),
  ('11111111-1111-1111-1111-111111111111', 'Solo', '2026-10-13 13:00+00', '2026-10-13 14:00+00', 'google', 'solo_20261013T130000Z'),
  ('11111111-1111-1111-1111-111111111111', 'SemSep', '2026-10-14 13:00+00', '2026-10-14 14:00+00', 'google', 'semseparador'),
  -- google com a mesma base, mas títulos diferentes: não agrupa
  ('11111111-1111-1111-1111-111111111111', 'Aula A', '2026-10-12 17:00+00', '2026-10-12 18:00+00', 'google', 'tit_20261012T170000Z'),
  ('11111111-1111-1111-1111-111111111111', 'Aula B', '2026-10-19 17:00+00', '2026-10-19 18:00+00', 'google', 'tit_20261019T170000Z'),
  -- plano com 2 partes: <base>:<data>
  ('11111111-1111-1111-1111-111111111111', 'Academia', '2026-10-12 15:00+00', '2026-10-12 16:00+00', 'plano', 'plan1:2026-10-12'),
  ('11111111-1111-1111-1111-111111111111', 'Academia', '2026-10-13 15:00+00', '2026-10-13 16:00+00', 'plano', 'plan1:2026-10-13'),
  -- plano com 3 partes e títulos iguais: <base>:<data>:<código> agrupa pela base + código
  ('11111111-1111-1111-1111-111111111111', 'Estudo C03', '2026-10-12 18:00+00', '2026-10-12 19:00+00', 'plano', 'estudo:2026-10-12:C03'),
  ('11111111-1111-1111-1111-111111111111', 'Estudo C03', '2026-10-14 18:00+00', '2026-10-14 19:00+00', 'plano', 'estudo:2026-10-14:C03'),
  -- provas: mesma base "prova", códigos e títulos diferentes: não agrupam
  ('11111111-1111-1111-1111-111111111111', 'Prova de Cálculo', '2026-10-20 12:00+00', '2026-10-20 14:00+00', 'plano', 'prova:2026-10-20:M02'),
  ('11111111-1111-1111-1111-111111111111', 'Prova de Física', '2026-10-22 12:00+00', '2026-10-22 14:00+00', 'plano', 'prova:2026-10-22:M03'),
  -- mesma chave e mesmo título, mas horário local diferente: não agrupa
  ('11111111-1111-1111-1111-111111111111', 'NP', '2026-10-12 15:00+00', '2026-10-12 16:00+00', 'plano', 'np:2026-10-12'),
  ('11111111-1111-1111-1111-111111111111', 'NP', '2026-10-13 16:00+00', '2026-10-13 17:00+00', 'plano', 'np:2026-10-13'),
  ('11111111-1111-1111-1111-111111111111', 'Manual', '2026-10-15 15:00+00', '2026-10-15 16:00+00', 'manual', 'abc_manual1'),
  ('11111111-1111-1111-1111-111111111111', 'Manual', '2026-10-16 15:00+00', '2026-10-16 16:00+00', 'manual', 'abc_manual2'),
  ('22222222-2222-2222-2222-222222222222', 'Reunião', '2026-10-12 13:00+00', '2026-10-12 14:00+00', 'google', 'abc_20261012T130000Z');

select public.backfill_event_series();

select is(
  (select count(distinct series_id)::int from events
    where user_id = '11111111-1111-1111-1111-111111111111' and external_id like 'abc\_2%' and series_id is not null),
  1, 'google: duas linhas com a mesma base, título e horário viram uma série');
select is(
  (select count(*)::int from events
    where user_id = '11111111-1111-1111-1111-111111111111' and external_id like 'abc\_2%' and series_id is not null),
  2, 'google: as duas linhas recebem série');
select is(
  (select series_id from events where title = 'Solo'), null, 'base com 1 linha só fica sem série');
select is(
  (select series_id from events where title = 'SemSep'), null, 'external_id sem separador fica sem série');
select is(
  (select count(series_id)::int from events where title in ('Aula A', 'Aula B')),
  0, 'google: mesma base com títulos diferentes não agrupa');
select is(
  (select count(distinct series_id)::int from events where title = 'Academia' and series_id is not null),
  1, 'plano: base antes da data (2 partes) agrupa');
select is(
  (select count(distinct series_id)::int from events where title = 'Estudo C03' and series_id is not null),
  1, 'plano: <base>:<data>:<código> com títulos iguais agrupa em uma série');
select is(
  (select count(*)::int from events where title = 'Estudo C03' and series_id is not null),
  2, 'plano: as duas ocorrências de <base>:<código> recebem a série');
select is(
  (select count(series_id)::int from events where external_id like 'prova:%'),
  0, 'plano: provas prova:<data>:<código> com títulos diferentes não agrupam');
select is(
  (select count(series_id)::int from events where title = 'NP'),
  0, 'horário local de início diferente não agrupa');
select is(
  (select count(series_id)::int from events where source = 'manual'), 0, 'só google e plano são agrupados');
select is(
  (select series_id from events where user_id = '22222222-2222-2222-2222-222222222222'), null,
  'outro usuário com a mesma base não entra na série');
select isnt(
  (select series_id from events where external_id = 'abc_20261012T130000Z' and user_id = '11111111-1111-1111-1111-111111111111'),
  (select series_id from events where external_id = 'plan1:2026-10-12'),
  'séries de fontes diferentes não se misturam');

select public.backfill_event_series();
select is(
  (select count(distinct series_id)::int from events where series_id is not null), 3,
  'rodar de novo não muda nada (idempotente)');

select throws_ok(
  $$ insert into events (user_id, title, starts_at, ends_at, recurrence)
     values ('11111111-1111-1111-1111-111111111111', 'Ruim', now(), now(), '[1,2]'::jsonb) $$,
  '23514', null, 'recurrence precisa ser um objeto jsonb');
select lives_ok(
  $$ insert into events (user_id, title, starts_at, ends_at, series_id, recurrence)
     values ('11111111-1111-1111-1111-111111111111', 'Boa', now(), now(), gen_random_uuid(),
             '{"freq":"weekly","days":[2,4],"until":"2026-12-15","count":null}'::jsonb) $$,
  'recurrence objeto é aceito');

select * from finish();
rollback;
