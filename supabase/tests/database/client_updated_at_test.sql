-- Último ganha: client_updated_at em todas as tabelas sincronizadas pelo app e o gatilho que ignora
-- atualização mais velha que a gravada. Escrita sem o campo (ponte, MCP, SQL) recebe now().
begin;
create extension if not exists pgtap with schema extensions;
select plan(27);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev');

-- ===== Esquema: as 14 tabelas sincronizadas =================================
create temp table sincronizadas (t text);
insert into sincronizadas values
  ('spaces'), ('notes'), ('tasks'), ('events'), ('event_tags'), ('workouts'), ('workout_exercises'),
  ('workout_sessions'), ('set_logs'), ('shopping_lists'), ('shopping_items'), ('user_settings'),
  ('wake_plans'), ('wake_overrides');

select is(
  (select count(*)::int from information_schema.columns c join sincronizadas s on s.t = c.table_name
    where c.table_schema = 'public' and c.column_name = 'client_updated_at'
      and c.data_type = 'timestamp with time zone' and c.is_nullable = 'NO' and c.column_default like 'now()%'),
  14, 'client_updated_at timestamptz not null default now() nas 14 tabelas');
select is(
  (select count(*)::int from pg_trigger g join pg_class k on k.oid = g.tgrelid join sincronizadas s on s.t = k.relname
    where k.relnamespace = 'public'::regnamespace and g.tgname = 'z_client_updated_at' and not g.tgisinternal),
  14, 'gatilho z_client_updated_at nas 14 tabelas');
select is(
  (select count(*)::int from pg_publication_tables p join sincronizadas s on s.t = p.tablename
    where p.pubname = 'supabase_realtime' and p.schemaname = 'public'),
  14, 'as 14 tabelas estão na publicação realtime (uma vez cada)');
select is(
  (select count(*)::int from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public'
     and tablename = 'shopping_frequent'),
  1, 'shopping_frequent continua na publicação (só leitura no app)');

-- ===== Insert normal ========================================================
insert into tasks (id, user_id, title) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Original');
select cmp_ok(
  (select client_updated_at from tasks where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  '>', now() - interval '1 minute', 'insert sem o campo recebe now()');

insert into tasks (id, user_id, title, client_updated_at) values
  ('aaaaaaaa-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'Dia 1', '2026-01-01T10:00:00Z');
select is(
  (select client_updated_at from tasks where id = 'aaaaaaaa-0000-0000-0000-000000000002'),
  '2026-01-01T10:00:00Z'::timestamptz, 'insert com o campo guarda o valor do aparelho');

-- ===== Atualização mais nova vence ==========================================
update tasks set title = 'Dia 2', client_updated_at = '2026-01-02T10:00:00Z'
  where id = 'aaaaaaaa-0000-0000-0000-000000000002';
select is((select title from tasks where id = 'aaaaaaaa-0000-0000-0000-000000000002'),
  'Dia 2', 'mais nova vence: título novo');
select is((select client_updated_at from tasks where id = 'aaaaaaaa-0000-0000-0000-000000000002'),
  '2026-01-02T10:00:00Z'::timestamptz, 'mais nova vence: carimbo novo');

-- ===== Atualização mais velha é ignorada (a linha inteira) ===================
update tasks set title = 'Dia 1 tardio', description = 'velha', client_updated_at = '2026-01-01T12:00:00Z'
  where id = 'aaaaaaaa-0000-0000-0000-000000000002';
select is((select title from tasks where id = 'aaaaaaaa-0000-0000-0000-000000000002'),
  'Dia 2', 'mais velha é ignorada: título intacto');
select is((select description from tasks where id = 'aaaaaaaa-0000-0000-0000-000000000002'),
  '', 'mais velha é ignorada: nenhum outro campo muda');
select is((select client_updated_at from tasks where id = 'aaaaaaaa-0000-0000-0000-000000000002'),
  '2026-01-02T10:00:00Z'::timestamptz, 'mais velha é ignorada: carimbo intacto');

-- ignorada também não mexe em updated_at (o gatilho roda depois do touch_updated_at e desfaz tudo)
insert into tasks (id, user_id, title, updated_at, client_updated_at) values
  ('aaaaaaaa-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'Antiga',
   '2020-01-01T00:00:00Z', '2026-01-02T10:00:00Z');
update tasks set title = 'outra velha', client_updated_at = '2025-12-31T00:00:00Z'
  where id = 'aaaaaaaa-0000-0000-0000-000000000003';
select is((select updated_at from tasks where id = 'aaaaaaaa-0000-0000-0000-000000000003'),
  '2020-01-01T00:00:00Z'::timestamptz, 'mais velha ignorada não altera updated_at');

-- ===== Carimbo igual (reenvio) não é "mais velho" ============================
update tasks set title = 'Mesmo carimbo', client_updated_at = '2026-01-02T10:00:00Z'
  where id = 'aaaaaaaa-0000-0000-0000-000000000002';
select cmp_ok((select client_updated_at from tasks where id = 'aaaaaaaa-0000-0000-0000-000000000002'),
  '>', now() - interval '1 minute', 'carimbo igual ao gravado = escrita sem o campo: vira now()');
select is((select title from tasks where id = 'aaaaaaaa-0000-0000-0000-000000000002'),
  'Mesmo carimbo', 'carimbo igual: a alteração é aplicada');

-- ===== Escrita sem o campo (ponte / MCP / SQL) vira now() ====================
update tasks set title = 'Pela ponte' where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select cmp_ok((select client_updated_at from tasks where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  '>', now() - interval '1 minute', 'update sem o campo carimba now()');
select is((select title from tasks where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'Pela ponte', 'update sem o campo é aplicado');

-- A ponte vence depois: um aparelho com relógio antigo não desfaz a escrita feita agora.
update tasks set title = 'Aparelho atrasado', client_updated_at = '2026-01-01T00:00:00Z'
  where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select is((select title from tasks where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  'Pela ponte', 'escrita da ponte (now) vence aparelho com carimbo mais antigo');

-- ===== Upsert com conflito (envio do app) ===================================
insert into workouts (id, user_id, name) values
  ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'A');
insert into workout_sessions (id, user_id, workout_id, workout_name, day) values
  ('cccccccc-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'bbbbbbbb-0000-0000-0000-000000000001', 'A', '2026-01-01');
insert into workout_exercises (id, user_id, workout_id, name) values
  ('dddddddd-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'bbbbbbbb-0000-0000-0000-000000000001', 'Supino');
insert into set_logs (id, user_id, session_id, exercise_id, exercise_name, set_index, reps, client_updated_at) values
  ('eeeeeeee-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'cccccccc-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001', 'Supino', 1, 10,
   '2026-01-02T10:00:00Z');

insert into set_logs (id, user_id, session_id, exercise_id, exercise_name, set_index, reps, client_updated_at) values
  ('eeeeeeee-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
   'cccccccc-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001', 'Supino', 1, 5,
   '2026-01-01T10:00:00Z')
  on conflict (session_id, exercise_id, set_index)
  do update set reps = excluded.reps, client_updated_at = excluded.client_updated_at;
select is((select reps from set_logs where id = 'eeeeeeee-0000-0000-0000-000000000001'),
  10, 'upsert com conflito: versão mais velha é ignorada');

insert into set_logs (id, user_id, session_id, exercise_id, exercise_name, set_index, reps, client_updated_at) values
  ('eeeeeeee-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111',
   'cccccccc-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001', 'Supino', 1, 12,
   '2026-01-03T10:00:00Z')
  on conflict (session_id, exercise_id, set_index)
  do update set reps = excluded.reps, client_updated_at = excluded.client_updated_at;
select is((select reps from set_logs where id = 'eeeeeeee-0000-0000-0000-000000000001'),
  12, 'upsert com conflito: versão mais nova vence');
select is((select count(*)::int from set_logs where session_id = 'cccccccc-0000-0000-0000-000000000001'),
  1, 'upsert não duplica a série');

-- ===== Chaves que não são "id" ==============================================
insert into user_settings (user_id, theme, client_updated_at)
  values ('11111111-1111-1111-1111-111111111111', 'safira', '2026-01-02T10:00:00Z');
insert into user_settings (user_id, theme, client_updated_at)
  values ('11111111-1111-1111-1111-111111111111', 'coral', '2026-01-01T10:00:00Z')
  on conflict (user_id) do update set theme = excluded.theme, client_updated_at = excluded.client_updated_at;
select is((select theme from user_settings where user_id = '11111111-1111-1111-1111-111111111111'),
  'safira', 'user_settings: upsert mais velho é ignorado');
insert into user_settings (user_id, theme, client_updated_at)
  values ('11111111-1111-1111-1111-111111111111', 'musgo', '2026-01-03T10:00:00Z')
  on conflict (user_id) do update set theme = excluded.theme, client_updated_at = excluded.client_updated_at;
select is((select theme from user_settings where user_id = '11111111-1111-1111-1111-111111111111'),
  'musgo', 'user_settings: upsert mais novo vence');

insert into wake_plans (id, user_id, label, days, time, echo_device_id) values
  ('ffffffff-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'Aula cedo', '{1,2,3,4,5}', '07:00', 'ECHO1');
insert into wake_overrides (plan_id, user_id, run_date, time, client_updated_at) values
  ('ffffffff-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '2026-10-13', '06:30',
   '2026-01-02T10:00:00Z');
insert into wake_overrides (plan_id, user_id, run_date, time, client_updated_at) values
  ('ffffffff-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '2026-10-13', '09:00',
   '2026-01-01T10:00:00Z')
  on conflict (plan_id, run_date) do update set time = excluded.time, client_updated_at = excluded.client_updated_at;
select is((select time::text from wake_overrides where plan_id = 'ffffffff-0000-0000-0000-000000000001' and run_date = '2026-10-13'),
  '06:30:00', 'wake_overrides (chave composta): upsert mais velho é ignorado');
insert into wake_overrides (plan_id, user_id, run_date, time, client_updated_at) values
  ('ffffffff-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '2026-10-13', '09:00',
   '2026-01-03T10:00:00Z')
  on conflict (plan_id, run_date) do update set time = excluded.time, client_updated_at = excluded.client_updated_at;
select is((select time::text from wake_overrides where plan_id = 'ffffffff-0000-0000-0000-000000000001' and run_date = '2026-10-13'),
  '09:00:00', 'wake_overrides: upsert mais novo vence');

-- ===== touch_updated_at continua valendo para atualização aceita =============
insert into spaces (id, user_id, name, updated_at) values
  ('99999999-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Cálculo', '2020-01-01');
update spaces set name = 'Cálculo 2', client_updated_at = now() + interval '1 hour'
  where id = '99999999-0000-0000-0000-000000000001';
select cmp_ok((select updated_at from spaces where id = '99999999-0000-0000-0000-000000000001'),
  '>', now() - interval '1 minute', 'atualização aceita continua carimbando updated_at');

-- ===== Tabela sem updated_at e a mais pesada: uma de cada tipo ================
insert into shopping_lists (id, user_id, name) values
  ('77777777-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Mercado');
update shopping_lists set name = 'Feira', client_updated_at = '2020-01-01' where id = '77777777-0000-0000-0000-000000000001';
select is((select name from shopping_lists where id = '77777777-0000-0000-0000-000000000001'),
  'Mercado', 'shopping_lists: atualização mais velha é ignorada');
insert into event_tags (id, user_id, name, color, client_updated_at) values
  ('88888888-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Aula', '#112233', '2026-01-02T10:00:00Z');
update event_tags set name = 'Velha', client_updated_at = '2026-01-01T10:00:00Z' where id = '88888888-0000-0000-0000-000000000001';
select is((select name from event_tags where id = '88888888-0000-0000-0000-000000000001'),
  'Aula', 'event_tags: atualização mais velha é ignorada');

select * from finish();
rollback;
