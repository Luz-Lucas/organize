begin;
create extension if not exists pgtap with schema extensions;
select plan(94);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.dev');

-- ===== Estrutura ==========================================================
select has_table('public', 'workouts', 'existe workouts');
select has_table('public', 'workout_exercises', 'existe workout_exercises');
select has_table('public', 'workout_sessions', 'existe workout_sessions');
select has_table('public', 'set_logs', 'existe set_logs');
select has_table('public', 'shopping_lists', 'existe shopping_lists');
select has_table('public', 'shopping_items', 'existe shopping_items');
select has_table('public', 'shopping_frequent', 'existe shopping_frequent');
select has_function('public', 'guess_shopping_section', array['uuid', 'text'], 'guess_shopping_section(uuid, text)');
select has_trigger('public', 'shopping_items', 'shopping_items_guess_section', 'gatilho before insert (seção)');
select has_trigger('public', 'shopping_items', 'shopping_items_track_frequent', 'gatilho after insert (frequente)');
select has_trigger('public', 'shopping_items', 'shopping_items_learn_section', 'gatilho after update of section (lembra)');
select has_index('public', 'workout_sessions', 'workout_sessions_user_day_idx', 'índice (user_id, day desc)');
select has_index('public', 'set_logs', 'set_logs_user_exercise_idx', 'índice (user_id, exercise_id, done_at desc)');
select is(
  (select count(*)::int from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename in ('workouts','workout_exercises','workout_sessions','set_logs',
                        'shopping_lists','shopping_items','shopping_frequent')),
  7, 'as 7 tabelas estão no realtime');
select is(
  (select count(*)::int from pg_class
    where oid in ('public.workouts'::regclass,'public.workout_exercises'::regclass,'public.workout_sessions'::regclass,
                  'public.set_logs'::regclass,'public.shopping_lists'::regclass,'public.shopping_items'::regclass,
                  'public.shopping_frequent'::regclass)
      and relrowsecurity),
  7, 'RLS ligada nas 7 tabelas');

-- ===== Padrões e checks (papel postgres) ==================================
insert into workouts (id, user_id, name) values
  ('a1000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Treino A'),
  ('b1000000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'Treino B do B');
select is((select position from workouts where id = 'a1000000-0000-0000-0000-000000000001'), 0, 'workouts.position padrão 0');
select throws_ok($$ insert into workouts (user_id, name) values ('11111111-1111-1111-1111-111111111111', '') $$,
  '23514', null, 'ficha com nome vazio é rejeitada');
select throws_ok($$ insert into workouts (user_id, name) values ('11111111-1111-1111-1111-111111111111', repeat('x', 61)) $$,
  '23514', null, 'ficha com 61 caracteres é rejeitada');

insert into workout_exercises (id, user_id, workout_id, name) values
  ('a2000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'a1000000-0000-0000-0000-000000000001', 'Supino');
select is(
  (select sets || '|' || reps || '|' || rest_seconds || '|' || notes || '|' || position
     from workout_exercises where id = 'a2000000-0000-0000-0000-000000000001'),
  '3|10|90||0', 'padrões do exercício: 3 séries, reps 10, descanso 90, sem nota, posição 0');
select is((select load_kg from workout_exercises where id = 'a2000000-0000-0000-0000-000000000001'), null,
  'carga planejada é opcional');
select throws_ok($$ insert into workout_exercises (user_id, workout_id, name, sets) values ('11111111-1111-1111-1111-111111111111', 'a1000000-0000-0000-0000-000000000001', 'x', 0) $$,
  '23514', null, 'sets 0 é rejeitado');
select throws_ok($$ insert into workout_exercises (user_id, workout_id, name, sets) values ('11111111-1111-1111-1111-111111111111', 'a1000000-0000-0000-0000-000000000001', 'x', 21) $$,
  '23514', null, 'sets 21 é rejeitado');
select throws_ok($$ insert into workout_exercises (user_id, workout_id, name, reps) values ('11111111-1111-1111-1111-111111111111', 'a1000000-0000-0000-0000-000000000001', 'x', '') $$,
  '23514', null, 'reps vazio é rejeitado');
select throws_ok($$ insert into workout_exercises (user_id, workout_id, name, load_kg) values ('11111111-1111-1111-1111-111111111111', 'a1000000-0000-0000-0000-000000000001', 'x', -1) $$,
  '23514', null, 'carga negativa é rejeitada');
select throws_ok($$ insert into workout_exercises (user_id, workout_id, name, rest_seconds) values ('11111111-1111-1111-1111-111111111111', 'a1000000-0000-0000-0000-000000000001', 'x', 901) $$,
  '23514', null, 'descanso 901 é rejeitado');
select throws_ok($$ insert into workout_exercises (user_id, workout_id, name) values ('11111111-1111-1111-1111-111111111111', 'a1000000-0000-0000-0000-000000000001', repeat('x', 81)) $$,
  '23514', null, 'exercício com nome de 81 caracteres é rejeitado');

insert into workout_sessions (id, user_id, workout_id, workout_name, day) values
  ('a3000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'a1000000-0000-0000-0000-000000000001', 'Treino A', '2026-10-19'),
  ('b3000000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'b1000000-0000-0000-0000-000000000001', 'Treino B do B', '2026-10-19');
select isnt((select started_at from workout_sessions where id = 'a3000000-0000-0000-0000-000000000001'), null, 'started_at preenchido');
select is((select finished_at from workout_sessions where id = 'a3000000-0000-0000-0000-000000000001'), null, 'sessão nasce em andamento');
select throws_ok($$ insert into workout_sessions (user_id, workout_name, day) values ('11111111-1111-1111-1111-111111111111', '', '2026-10-19') $$,
  '23514', null, 'sessão com nome vazio é rejeitada');

insert into set_logs (id, user_id, session_id, exercise_id, exercise_name, set_index, reps, load_kg) values
  ('a4000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'a3000000-0000-0000-0000-000000000001',
   'a2000000-0000-0000-0000-000000000001', 'Supino', 1, 10, 40);
select isnt((select done_at from set_logs where id = 'a4000000-0000-0000-0000-000000000001'), null, 'done_at preenchido');
select throws_ok($$ insert into set_logs (user_id, session_id, exercise_id, exercise_name, set_index) values ('11111111-1111-1111-1111-111111111111', 'a3000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000001', 'Supino', 1) $$,
  '23505', null, 'mesma série (sessão, exercício, índice) não repete');
select throws_ok($$ insert into set_logs (user_id, session_id, exercise_name, set_index) values ('11111111-1111-1111-1111-111111111111', 'a3000000-0000-0000-0000-000000000001', 'Supino', 0) $$,
  '23514', null, 'set_index 0 é rejeitado');
select throws_ok($$ insert into set_logs (user_id, session_id, exercise_name, set_index, reps) values ('11111111-1111-1111-1111-111111111111', 'a3000000-0000-0000-0000-000000000001', 'Supino', 2, 1000) $$,
  '23514', null, 'reps 1000 é rejeitado');

-- ===== Cascades ===========================================================
-- Apagar o exercício guarda a série (o nome fica em exercise_name).
delete from workout_exercises where id = 'a2000000-0000-0000-0000-000000000001';
select is((select exercise_id from set_logs where id = 'a4000000-0000-0000-0000-000000000001'), null,
  'apagar o exercício zera exercise_id da série (set null)');
select is((select exercise_name from set_logs where id = 'a4000000-0000-0000-0000-000000000001'), 'Supino',
  'a série guarda o nome do exercício');
-- Apagar a ficha mantém a sessão.
insert into workout_exercises (id, user_id, workout_id, name) values
  ('a2000000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'a1000000-0000-0000-0000-000000000001', 'Remada');
delete from workouts where id = 'a1000000-0000-0000-0000-000000000001';
select is((select count(*)::int from workout_exercises where id = 'a2000000-0000-0000-0000-000000000002'), 0,
  'apagar a ficha apaga os exercícios (cascade)');
select is((select count(*)::int from workout_sessions where id = 'a3000000-0000-0000-0000-000000000001'), 1,
  'apagar a ficha mantém a sessão');
select is((select workout_id from workout_sessions where id = 'a3000000-0000-0000-0000-000000000001'), null,
  'a sessão fica sem ficha (set null)');
select is((select workout_name from workout_sessions where id = 'a3000000-0000-0000-0000-000000000001'), 'Treino A',
  'a sessão guarda o nome da ficha');
delete from workout_sessions where id = 'a3000000-0000-0000-0000-000000000001';
select is((select count(*)::int from set_logs where session_id = 'a3000000-0000-0000-0000-000000000001'), 0,
  'apagar a sessão apaga as séries (cascade)');

-- Compras: checks e cascade
insert into shopping_lists (id, user_id, name) values
  ('a5000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Mercado'),
  ('b5000000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'Mercado');
select is((select section_order from shopping_lists where id = 'a5000000-0000-0000-0000-000000000001'), null,
  'ordem das seções é opcional');
select throws_ok($$ insert into shopping_lists (user_id, name) values ('11111111-1111-1111-1111-111111111111', 'MERCADO') $$,
  '23505', null, 'nome de lista repetido (sem caixa) é rejeitado');
select throws_ok($$ insert into shopping_lists (user_id, name) values ('11111111-1111-1111-1111-111111111111', repeat('x', 41)) $$,
  '23514', null, 'lista com 41 caracteres é rejeitada');
select lives_ok($$ update shopping_lists set section_order = array['padaria','hortifruti'] where id = 'a5000000-0000-0000-0000-000000000001' $$,
  'ordem de seções válida é aceita');
select throws_ok($$ update shopping_lists set section_order = array['padaria','xpto'] where id = 'a5000000-0000-0000-0000-000000000001' $$,
  '23514', null, 'ordem com seção inexistente é rejeitada');

insert into shopping_items (id, user_id, list_id, name, section) values
  ('a6000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'a5000000-0000-0000-0000-000000000001', 'Teste', 'outros');
select is((select checked::text || '|' || quantity || '|' || position from shopping_items where id = 'a6000000-0000-0000-0000-000000000001'),
  'false||0', 'padrões do item: não marcado, sem quantidade, posição 0');
select throws_ok($$ insert into shopping_items (user_id, list_id, name, section) values ('11111111-1111-1111-1111-111111111111', 'a5000000-0000-0000-0000-000000000001', 'x', 'xpto') $$,
  '23514', null, 'seção inválida é rejeitada');
select throws_ok($$ insert into shopping_items (user_id, list_id, name, quantity) values ('11111111-1111-1111-1111-111111111111', 'a5000000-0000-0000-0000-000000000001', 'x', repeat('1', 31)) $$,
  '23514', null, 'quantidade com 31 caracteres é rejeitada');
select throws_ok($$ insert into shopping_items (user_id, list_id, name) values ('11111111-1111-1111-1111-111111111111', 'a5000000-0000-0000-0000-000000000001', '') $$,
  '23514', null, 'item sem nome é rejeitado');
delete from shopping_lists where id = 'a5000000-0000-0000-0000-000000000001';
select is((select count(*)::int from shopping_items where id = 'a6000000-0000-0000-0000-000000000001'), 0,
  'apagar a lista apaga os itens (cascade)');
insert into shopping_lists (id, user_id, name) values
  ('a5000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Mercado');

-- ===== Palpite de seção ===================================================
select is(public.guess_shopping_section('11111111-1111-1111-1111-111111111111', 'leite'), 'frios', 'leite -> frios');
select is(public.guess_shopping_section('11111111-1111-1111-1111-111111111111', 'água sanitária'), 'limpeza', 'água sanitária -> limpeza');
select is(public.guess_shopping_section('11111111-1111-1111-1111-111111111111', 'Pão francês'), 'padaria', 'Pão francês -> padaria');
select is(public.guess_shopping_section('11111111-1111-1111-1111-111111111111', 'água com gás'), 'bebidas', 'água com gás -> bebidas');
select is(public.guess_shopping_section('11111111-1111-1111-1111-111111111111', 'macarrão'), 'mercearia', 'macarrão não vira maçã');
select is(public.guess_shopping_section('11111111-1111-1111-1111-111111111111', 'Maçã'), 'hortifruti', 'maçã -> hortifruti');
select is(public.guess_shopping_section('11111111-1111-1111-1111-111111111111', 'pasta de dente'), 'higiene', 'pasta de dente -> higiene');
select is(public.guess_shopping_section('11111111-1111-1111-1111-111111111111', 'pizza congelada'), 'congelados', 'pizza congelada -> congelados');
select is(public.guess_shopping_section('11111111-1111-1111-1111-111111111111', 'molho de tomate'), 'mercearia', 'molho de tomate -> mercearia');
select is(public.guess_shopping_section('11111111-1111-1111-1111-111111111111', 'produto novo'), 'outros', 'ovo dentro de "novo" não casa');
select is(public.guess_shopping_section('11111111-1111-1111-1111-111111111111', 'coisa qualquer'), 'outros', 'sem palavra-chave -> outros');

-- ===== Gatilhos: seção, frequente, lembrança ==============================
insert into shopping_items (id, user_id, list_id, name) values
  ('a6000000-0000-0000-0000-000000000010', '11111111-1111-1111-1111-111111111111', 'a5000000-0000-0000-0000-000000000001', 'Leite');
select is((select section from shopping_items where id = 'a6000000-0000-0000-0000-000000000010'), 'frios',
  'seção nula vira o palpite (Leite -> frios)');
insert into shopping_items (id, user_id, list_id, name, section) values
  ('a6000000-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111', 'a5000000-0000-0000-0000-000000000001', 'Sabão', 'outros');
select is((select section from shopping_items where id = 'a6000000-0000-0000-0000-000000000011'), 'outros',
  'seção informada é respeitada');

select is((select times from shopping_frequent where user_id = '11111111-1111-1111-1111-111111111111' and name_key = 'leite'), 1,
  'primeiro item cria o frequente com times 1');
select is((select name || '|' || section from shopping_frequent where user_id = '11111111-1111-1111-1111-111111111111' and name_key = 'leite'),
  'Leite|frios', 'frequente guarda nome e seção');
insert into shopping_items (user_id, list_id, name) values
  ('11111111-1111-1111-1111-111111111111', 'a5000000-0000-0000-0000-000000000001', 'LEITE');
select is((select times from shopping_frequent where user_id = '11111111-1111-1111-1111-111111111111' and name_key = 'leite'), 2,
  'repetir o nome (outra caixa) soma times');
select is((select count(*)::int from shopping_frequent where user_id = '11111111-1111-1111-1111-111111111111' and name_key = 'leite'), 1,
  'continua um frequente só');
select is((select name from shopping_frequent where user_id = '11111111-1111-1111-1111-111111111111' and name_key = 'leite'), 'LEITE',
  'o frequente guarda o nome mais recente');

-- Corrigir a seção: o app lembra.
update shopping_items set section = 'bebidas' where id = 'a6000000-0000-0000-0000-000000000010';
select is((select section from shopping_frequent where user_id = '11111111-1111-1111-1111-111111111111' and name_key = 'leite'), 'bebidas',
  'corrigir a seção atualiza o frequente');
insert into shopping_items (id, user_id, list_id, name) values
  ('a6000000-0000-0000-0000-000000000012', '11111111-1111-1111-1111-111111111111', 'a5000000-0000-0000-0000-000000000001', 'leite');
select is((select section from shopping_items where id = 'a6000000-0000-0000-0000-000000000012'), 'bebidas',
  'o próximo "leite" já nasce na seção corrigida');
select is(public.guess_shopping_section('22222222-2222-2222-2222-222222222222', 'leite'), 'frios',
  'a lembrança de A não vaza para B');

-- ===== RLS ================================================================
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select is((select count(*)::int from workouts where user_id <> '11111111-1111-1111-1111-111111111111'), 0, 'A não vê fichas de B');
select is((select count(*)::int from workout_sessions where user_id <> '11111111-1111-1111-1111-111111111111'), 0, 'A não vê sessões de B');
select is((select count(*)::int from shopping_lists where user_id <> '11111111-1111-1111-1111-111111111111'), 0, 'A não vê listas de B');

select lives_ok($$ insert into workouts (id, name) values ('a1000000-0000-0000-0000-0000000000a1', 'Meu treino') $$, 'A cria ficha (user_id por auth.uid())');
select lives_ok($$ insert into workout_exercises (id, workout_id, name) values ('a2000000-0000-0000-0000-0000000000a1', 'a1000000-0000-0000-0000-0000000000a1', 'Agachamento') $$,
  'A cria exercício na própria ficha');
select lives_ok($$ insert into workout_sessions (id, workout_id, workout_name, day) values ('a3000000-0000-0000-0000-0000000000a1', 'a1000000-0000-0000-0000-0000000000a1', 'Meu treino', '2026-10-19') $$,
  'A abre sessão da própria ficha');
select lives_ok($$ insert into set_logs (session_id, exercise_id, exercise_name, set_index) values ('a3000000-0000-0000-0000-0000000000a1', 'a2000000-0000-0000-0000-0000000000a1', 'Agachamento', 1) $$,
  'A registra série na própria sessão');
select lives_ok($$ insert into shopping_items (list_id, name) values ('a5000000-0000-0000-0000-000000000001', 'Arroz') $$, 'A adiciona item na própria lista (gatilho roda como authenticated)');
select is((select section from shopping_items where name = 'Arroz'), 'mercearia', 'seção decidida no banco para authenticated');

select throws_ok($$ insert into workouts (user_id, name) values ('22222222-2222-2222-2222-222222222222', 'Invasão') $$,
  '42501', null, 'A não cria ficha em nome de B');
select throws_ok($$ insert into workout_exercises (workout_id, name) values ('b1000000-0000-0000-0000-000000000001', 'Invasão') $$,
  '42501', null, 'A não põe exercício na ficha de B');
select throws_ok($$ insert into workout_sessions (workout_id, workout_name, day) values ('b1000000-0000-0000-0000-000000000001', 'x', '2026-10-19') $$,
  '42501', null, 'A não abre sessão apontando para a ficha de B');
select throws_ok($$ insert into set_logs (session_id, exercise_name, set_index) values ('b3000000-0000-0000-0000-000000000001', 'x', 1) $$,
  '42501', null, 'A não registra série na sessão de B');
select throws_ok($$ insert into shopping_items (list_id, name) values ('b5000000-0000-0000-0000-000000000001', 'Invasão') $$,
  '42501', null, 'A não põe item na lista de B');
select throws_ok($$ update workout_sessions set workout_id = 'b1000000-0000-0000-0000-000000000001' where id = 'a3000000-0000-0000-0000-0000000000a1' $$,
  '42501', null, 'A não aponta a própria sessão para a ficha de B');
select throws_ok($$ insert into shopping_frequent (user_id, name_key, name, section) values ('22222222-2222-2222-2222-222222222222', 'x', 'x', 'outros') $$,
  '42501', null, 'A não cria frequente em nome de B');
select throws_ok($$ select public.guess_shopping_section('22222222-2222-2222-2222-222222222222', 'leite') $$,
  '42501', null, 'authenticated não chama guess_shopping_section');

-- B não mexe nas coisas de A
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
update workouts set name = 'Invadida' where id = 'a1000000-0000-0000-0000-0000000000a1';
delete from shopping_items where list_id = 'a5000000-0000-0000-0000-000000000001';
select is((select count(*)::int from workouts where id = 'a1000000-0000-0000-0000-0000000000a1'), 0, 'B não enxerga a ficha de A');
select is((select count(*)::int from shopping_frequent), 0, 'B não enxerga frequentes de A');
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
select is((select name from workouts where id = 'a1000000-0000-0000-0000-0000000000a1'), 'Meu treino', 'B não renomeou a ficha de A');
select is((select count(*)::int from shopping_items where list_id = 'a5000000-0000-0000-0000-000000000001'), 5, 'B não apagou itens de A');

reset role;
set local role anon;
select throws_ok($$ select count(*) from public.workouts $$, '42501', null, 'anon não lê workouts');
select throws_ok($$ select count(*) from public.shopping_items $$, '42501', null, 'anon não lê shopping_items');

select * from finish();
rollback;
