begin;
create extension if not exists pgtap with schema extensions;
select plan(93);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.dev'),
  ('33333333-3333-3333-3333-333333333333', 'c@test.dev'),
  ('44444444-4444-4444-4444-444444444444', 'd@test.dev'),
  ('55555555-5555-5555-5555-555555555555', 'e@test.dev'),
  ('66666666-6666-6666-6666-666666666666', 'f@test.dev');

-- ===== Estrutura ==========================================================
select has_table('public', 'event_tags', 'existe a tabela event_tags');
select has_column('public', 'events', 'tag_id', 'events tem tag_id');
select has_index('public', 'events', 'events_tag_idx', 'índice em events.tag_id');
select has_function('public', 'seed_event_tags', array['uuid'], 'seed_event_tags(uuid)');
select has_function('public', 'classify_events', array['uuid'], 'classify_events(uuid)');
select has_function('public', 'seed_my_event_tags', array[]::text[], 'seed_my_event_tags() (RPC do app)');
select is(
  (select count(*)::int from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'event_tags'),
  1, 'event_tags está no realtime');
select is(
  (select relrowsecurity from pg_class where oid = 'public.event_tags'::regclass),
  true, 'RLS ligada em event_tags');

-- ===== Padrões e checks (papel postgres) ==================================
insert into event_tags (id, user_id, name, color) values
  ('a0000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Teste', '#112233');
select is((select role from event_tags where id = 'a0000000-0000-0000-0000-000000000001'), 'normal', 'role padrão é normal');
select is((select position from event_tags where id = 'a0000000-0000-0000-0000-000000000001'), 0, 'position padrão é 0');
select isnt((select created_at from event_tags where id = 'a0000000-0000-0000-0000-000000000001'), null, 'created_at preenchido');

select throws_ok(
  $$ insert into event_tags (user_id, name, color) values ('11111111-1111-1111-1111-111111111111', '', '#112233') $$,
  '23514', null, 'nome vazio é rejeitado');
select throws_ok(
  $$ insert into event_tags (user_id, name, color) values ('11111111-1111-1111-1111-111111111111', repeat('x', 41), '#112233') $$,
  '23514', null, 'nome com 41 caracteres é rejeitado');
select lives_ok(
  $$ insert into event_tags (user_id, name, color) values ('11111111-1111-1111-1111-111111111111', repeat('y', 40), '#aBcDeF') $$,
  'nome com 40 caracteres e cor com hex misto são aceitos');
select throws_ok(
  $$ insert into event_tags (user_id, name, color) values ('11111111-1111-1111-1111-111111111111', 'C1', 'vermelho') $$,
  '23514', null, 'cor por nome é rejeitada');
select throws_ok(
  $$ insert into event_tags (user_id, name, color) values ('11111111-1111-1111-1111-111111111111', 'C2', '#12345') $$,
  '23514', null, 'cor com 5 dígitos é rejeitada');
select throws_ok(
  $$ insert into event_tags (user_id, name, color) values ('11111111-1111-1111-1111-111111111111', 'C3', '112233') $$,
  '23514', null, 'cor sem # é rejeitada');
select throws_ok(
  $$ insert into event_tags (user_id, name, color) values ('11111111-1111-1111-1111-111111111111', 'C4', '#GG1122') $$,
  '23514', null, 'cor com dígito inválido é rejeitada');
select throws_ok(
  $$ insert into event_tags (user_id, name, color, role) values ('11111111-1111-1111-1111-111111111111', 'R1', '#112233', 'extra') $$,
  '23514', null, 'role inválido é rejeitado');
select lives_ok(
  $$ insert into event_tags (user_id, name, color, role) values
       ('11111111-1111-1111-1111-111111111111', 'R-main', '#112233', 'main'),
       ('11111111-1111-1111-1111-111111111111', 'R-sec', '#112233', 'secondary'),
       ('11111111-1111-1111-1111-111111111111', 'R-sea', '#112233', 'seasonal'),
       ('11111111-1111-1111-1111-111111111111', 'R-meet', '#112233', 'meeting') $$,
  'os cinco roles são aceitos');
select throws_ok(
  $$ insert into event_tags (user_id, name, color) values ('11111111-1111-1111-1111-111111111111', 'tEsTe', '#112233') $$,
  '23505', null, 'nome repetido (sem diferenciar caixa) é rejeitado para o mesmo usuário');
select lives_ok(
  $$ insert into event_tags (id, user_id, name, color) values ('b0000000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'Teste', '#112233') $$,
  'outro usuário pode usar o mesmo nome');

-- ===== ON DELETE SET NULL =================================================
insert into events (id, user_id, title, starts_at, ends_at, tag_id) values
  ('e0000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Com etiqueta',
   '2026-10-12 13:00+00', '2026-10-12 14:00+00', 'a0000000-0000-0000-0000-000000000001');
select is((select tag_id from events where id = 'e0000000-0000-0000-0000-000000000001'),
  'a0000000-0000-0000-0000-000000000001'::uuid, 'evento guarda o tag_id');
delete from event_tags where id = 'a0000000-0000-0000-0000-000000000001';
select is((select count(*)::int from events where id = 'e0000000-0000-0000-0000-000000000001'), 1,
  'excluir a etiqueta não apaga o evento');
select is((select tag_id from events where id = 'e0000000-0000-0000-0000-000000000001'), null,
  'excluir a etiqueta deixa o evento sem etiqueta (set null)');
select throws_ok(
  $$ update events set tag_id = 'a9999999-9999-9999-9999-999999999999' where id = 'e0000000-0000-0000-0000-000000000001' $$,
  '23503', null, 'tag_id inexistente é rejeitado (FK)');

-- ===== Semeadura: seed_event_tags(uid) ====================================
select is(public.seed_event_tags('33333333-3333-3333-3333-333333333333'), 4, 'semeia 4 etiquetas num usuário vazio');
select is(
  (select array_agg(name || '/' || role order by position) from event_tags
    where user_id = '33333333-3333-3333-3333-333333333333'),
  array['Aula/main', 'Academia/secondary', 'Sazonal/seasonal', 'Reunião/meeting'],
  'nomes, papéis e ordem iniciais');
select is(
  (select count(*)::int from event_tags
    where user_id = '33333333-3333-3333-3333-333333333333' and color ~ '^#[0-9A-F]{6}$'),
  4, 'cores iniciais são hex válidos');
select is(
  (select count(distinct color)::int from event_tags where user_id = '33333333-3333-3333-3333-333333333333'),
  4, 'cada etiqueta inicial tem uma cor diferente');
select is(public.seed_event_tags('33333333-3333-3333-3333-333333333333'), 0, 'rodar de novo não cria nada');
select is((select count(*)::int from event_tags where user_id = '33333333-3333-3333-3333-333333333333'), 4,
  'continua com 4 etiquetas após a segunda chamada');

-- Só cria as que faltam, por papel (mesmo renomeada ou recolorida a etiqueta existente fica como está).
insert into event_tags (user_id, name, color, role, position) values
  ('44444444-4444-4444-4444-444444444444', 'Faculdade', '#010203', 'main', 7);
select is(public.seed_event_tags('44444444-4444-4444-4444-444444444444'), 3, 'cria só as 3 que faltam');
select is(
  (select name || '|' || color || '|' || position from event_tags
    where user_id = '44444444-4444-4444-4444-444444444444' and role = 'main'),
  'Faculdade|#010203|7', 'a etiqueta de papel main já existente não é tocada nem duplicada');
select is(
  (select count(*)::int from event_tags where user_id = '44444444-4444-4444-4444-444444444444' and role = 'main'),
  1, 'continua uma só etiqueta main');

-- Nome já usado por outra etiqueta (papel normal) não derruba a semeadura.
insert into event_tags (user_id, name, color) values
  ('55555555-5555-5555-5555-555555555555', 'academia', '#010203');
select lives_ok($$ select public.seed_event_tags('55555555-5555-5555-5555-555555555555') $$,
  'conflito de nome não gera erro');
select is((select count(*)::int from event_tags where user_id = '55555555-5555-5555-5555-555555555555'
            and lower(name) = 'academia'), 1, 'sem etiqueta duplicada por nome');

-- ===== Classificação: classify_events(uid) ================================
-- D tem as 4 etiquetas (3 semeadas + a "Faculdade" de papel main); completa-se aqui para ficar tudo certo.
select lives_ok($$ select public.seed_event_tags('44444444-4444-4444-4444-444444444444') $$, 'D com todas as etiquetas');

create function pg_temp.mk(p_title text, p_all_day boolean default false, p_tag text default null)
returns void language sql as $$
  insert into public.events (user_id, title, starts_at, ends_at, all_day, tag_id)
  values ('44444444-4444-4444-4444-444444444444', p_title, '2026-10-12 13:00+00', '2026-10-12 14:00+00', p_all_day,
          (select id from public.event_tags where user_id = '44444444-4444-4444-4444-444444444444' and name = p_tag));
$$;
create function pg_temp.tag_of(p_title text) returns text language sql as $$
  select t.name from public.events e left join public.event_tags t on t.id = e.tag_id
   where e.user_id = '44444444-4444-4444-4444-444444444444' and e.title = p_title;
$$;

-- Aula
select pg_temp.mk('M02 Cálculo II');
select pg_temp.mk('C03');
select pg_temp.mk('H01 - Aula');
select pg_temp.mk('Estudo C03');
select pg_temp.mk('estudo de física');
-- não é aula
select pg_temp.mk('m02 cálculo');
select pg_temp.mk('M022 Cálculo');
select pg_temp.mk('Hora de Estudo');
-- Academia
select pg_temp.mk('Academia');
select pg_temp.mk('ACADEMIA - perna');
select pg_temp.mk('Treino na Acadêmia');
select pg_temp.mk('Ir na academia');
-- Reunião
select pg_temp.mk('Reunião de equipe');
select pg_temp.mk('REUNIÃO');
select pg_temp.mk('Reuniao semanal');
select pg_temp.mk('Cogestão');
select pg_temp.mk('cogestao do mês');
select pg_temp.mk('NP1');
select pg_temp.mk('np 2');
select pg_temp.mk('ReuNP 1');
select pg_temp.mk('Sinpro');
-- Sazonal
select pg_temp.mk('Dia livre', true);
select pg_temp.mk('Viagem a SP');
select pg_temp.mk('Feriado de Natal');
select pg_temp.mk('Fora da cidade');
select pg_temp.mk('FORA DA CIDADE até sexta');
-- Precedência: Aula > Academia > Reunião > Sazonal
select pg_temp.mk('M02 Reunião');
select pg_temp.mk('Academia na viagem');
select pg_temp.mk('Reunião de viagem');
select pg_temp.mk('Academia (dia todo)', true);
select pg_temp.mk('C05', true);
-- Sem regra / já etiquetado
select pg_temp.mk('Dentista');
select pg_temp.mk('M02 Já etiquetado', false, 'Sazonal');

-- Evento de outro usuário (C) e usuário sem etiquetas (B): nada acontece.
insert into events (user_id, title, starts_at, ends_at) values
  ('22222222-2222-2222-2222-222222222222', 'M02 Cálculo', '2026-10-12 13:00+00', '2026-10-12 14:00+00');
insert into events (user_id, title, starts_at, ends_at) values
  ('33333333-3333-3333-3333-333333333333', 'M02 Cálculo', '2026-10-12 13:00+00', '2026-10-12 14:00+00');

select is(public.classify_events('44444444-4444-4444-4444-444444444444'), 27, 'classify_events devolve quantos eventos etiquetou');

select is(pg_temp.tag_of('M02 Cálculo II'), 'Faculdade', 'código de matéria M02 -> Aula (etiqueta main)');
select is(pg_temp.tag_of('C03'), 'Faculdade', 'código sozinho (C03) -> Aula');
select is(pg_temp.tag_of('H01 - Aula'), 'Faculdade', 'H01 - Aula -> Aula');
select is(pg_temp.tag_of('Estudo C03'), 'Faculdade', 'começa com Estudo -> Aula');
select is(pg_temp.tag_of('estudo de física'), 'Faculdade', 'Estudo sem diferenciar caixa -> Aula');
select is(pg_temp.tag_of('m02 cálculo'), null, 'código em minúsculas não é código de matéria');
select is(pg_temp.tag_of('M022 Cálculo'), null, 'M022 não é código de matéria (\b)');
select is(pg_temp.tag_of('Hora de Estudo'), null, 'Estudo no meio do título não conta');

select is(pg_temp.tag_of('Academia'), 'Academia', 'academia -> Academia');
select is(pg_temp.tag_of('ACADEMIA - perna'), 'Academia', 'ACADEMIA em maiúsculas -> Academia');
select is(pg_temp.tag_of('Treino na Acadêmia'), 'Academia', 'Acadêmia com acento -> Academia');
select is(pg_temp.tag_of('Ir na academia'), 'Academia', 'academia no meio do título -> Academia');

select is(pg_temp.tag_of('Reunião de equipe'), 'Reunião', 'reunião -> Reunião');
select is(pg_temp.tag_of('REUNIÃO'), 'Reunião', 'REUNIÃO em maiúsculas -> Reunião');
select is(pg_temp.tag_of('Reuniao semanal'), 'Reunião', 'reuniao sem acento -> Reunião');
select is(pg_temp.tag_of('Cogestão'), 'Reunião', 'cogestão -> Reunião');
select is(pg_temp.tag_of('cogestao do mês'), 'Reunião', 'cogestao sem acento -> Reunião');
select is(pg_temp.tag_of('NP1'), 'Reunião', 'começa com NP -> Reunião');
select is(pg_temp.tag_of('np 2'), 'Reunião', 'np minúsculo no começo -> Reunião');
select is(pg_temp.tag_of('ReuNP 1'), 'Reunião', 'começa com ReuNP -> Reunião');
select is(pg_temp.tag_of('Sinpro'), null, 'np no meio do título não conta');

select is(pg_temp.tag_of('Dia livre'), 'Sazonal', 'evento de dia inteiro -> Sazonal');
select is(pg_temp.tag_of('Viagem a SP'), 'Sazonal', 'viagem -> Sazonal');
select is(pg_temp.tag_of('Feriado de Natal'), 'Sazonal', 'feriado -> Sazonal');
select is(pg_temp.tag_of('Fora da cidade'), 'Sazonal', 'fora da cidade -> Sazonal');
select is(pg_temp.tag_of('FORA DA CIDADE até sexta'), 'Sazonal', 'FORA DA CIDADE em maiúsculas -> Sazonal');

select is(pg_temp.tag_of('M02 Reunião'), 'Faculdade', 'precedência: Aula antes de Reunião');
select is(pg_temp.tag_of('Academia na viagem'), 'Academia', 'precedência: Academia antes de Sazonal');
select is(pg_temp.tag_of('Reunião de viagem'), 'Reunião', 'precedência: Reunião antes de Sazonal');
select is(pg_temp.tag_of('Academia (dia todo)'), 'Academia', 'precedência: Academia antes de dia inteiro');
select is(pg_temp.tag_of('C05'), 'Faculdade', 'precedência: Aula antes de dia inteiro');

select is(pg_temp.tag_of('Dentista'), null, 'sem regra -> sem etiqueta');
select is(pg_temp.tag_of('M02 Já etiquetado'), 'Sazonal', 'evento que já tem etiqueta não é reclassificado');
select is((select tag_id from events where user_id = '22222222-2222-2222-2222-222222222222'), null,
  'eventos de outro usuário não são tocados');
select is(public.classify_events('44444444-4444-4444-4444-444444444444'), 0, 'segunda chamada não muda nada (idempotente)');
select is(public.classify_events('33333333-3333-3333-3333-333333333333'), 1, 'usa as etiquetas do próprio usuário (C)');
select is(public.classify_events('22222222-2222-2222-2222-222222222222'), 0, 'usuário sem etiquetas: nada a fazer');

insert into events (user_id, title, starts_at, ends_at) values
  ('66666666-6666-6666-6666-666666666666', 'M03 Aula do F', '2026-10-12 13:00+00', '2026-10-12 14:00+00');

-- ===== RLS ================================================================
-- (usuário A ainda tem 'Teste'(apagada), 'yyyy…', 'R-*' etc. criadas acima; B tem 'Teste')
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select is((select count(*)::int from event_tags where user_id <> '11111111-1111-1111-1111-111111111111'), 0,
  'A não vê etiquetas de outros');
select lives_ok(
  $$ insert into event_tags (id, name, color) values ('a0000000-0000-0000-0000-0000000000a1', 'Minha', '#00AA00') $$,
  'A cria uma etiqueta');
select is((select user_id from event_tags where id = 'a0000000-0000-0000-0000-0000000000a1'),
  '11111111-1111-1111-1111-111111111111'::uuid, 'user_id vem de auth.uid()');
select throws_ok(
  $$ insert into event_tags (user_id, name, color) values ('22222222-2222-2222-2222-222222222222', 'Invasão', '#00AA00') $$,
  '42501', null, 'A não cria etiqueta em nome de B');
select lives_ok(
  $$ insert into events (id, title, starts_at, ends_at, tag_id)
     values ('e0000000-0000-0000-0000-0000000000a1', 'Do A', now(), now() + interval '1 hour', 'a0000000-0000-0000-0000-0000000000a1') $$,
  'A etiqueta o próprio evento com a própria etiqueta');
select throws_ok(
  $$ update events set tag_id = 'b0000000-0000-0000-0000-000000000001' where id = 'e0000000-0000-0000-0000-0000000000a1' $$,
  '42501', null, 'A não aponta o evento para a etiqueta de B');
select throws_ok(
  $$ insert into events (title, starts_at, ends_at, tag_id)
     values ('Roubo', now(), now() + interval '1 hour', 'b0000000-0000-0000-0000-000000000001') $$,
  '42501', null, 'A não cria evento com a etiqueta de B');
select lives_ok(
  $$ update events set tag_id = null where id = 'e0000000-0000-0000-0000-0000000000a1' $$,
  'A tira a etiqueta do próprio evento');

-- B não mexe nas etiquetas de A
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
update event_tags set name = 'Invadida' where id = 'a0000000-0000-0000-0000-0000000000a1';
delete from event_tags where id = 'a0000000-0000-0000-0000-0000000000a1';
select is((select count(*)::int from event_tags where id = 'a0000000-0000-0000-0000-0000000000a1'), 0,
  'B não enxerga a etiqueta de A');
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
select is((select name from event_tags where id = 'a0000000-0000-0000-0000-0000000000a1'), 'Minha',
  'B não renomeou nem apagou a etiqueta de A');

-- Funções internas não são chamáveis pelo app
select throws_ok($$ select public.seed_event_tags('11111111-1111-1111-1111-111111111111') $$,
  '42501', null, 'authenticated não chama seed_event_tags(uuid)');
select throws_ok($$ select public.classify_events('11111111-1111-1111-1111-111111111111') $$,
  '42501', null, 'authenticated não chama classify_events(uuid)');

-- RPC do app: semeia e classifica só para quem chama
select set_config('request.jwt.claims', '{"sub":"66666666-6666-6666-6666-666666666666","role":"authenticated"}', true);
select is(public.seed_my_event_tags(), 4, 'seed_my_event_tags cria as 4 etiquetas de quem chama');
select is((select count(*)::int from event_tags), 4, 'F vê só as próprias 4');
select is(public.seed_my_event_tags(), 0, 'seed_my_event_tags é idempotente');
select is((select tag_id from events where title = 'M03 Aula do F') = (select id from event_tags where role = 'main'), true,
  'seed_my_event_tags também classifica os eventos existentes de quem chama');

reset role;
set local role anon;
select throws_ok($$ select count(*) from public.event_tags $$, '42501', null, 'anon não lê event_tags');

select * from finish();
rollback;
