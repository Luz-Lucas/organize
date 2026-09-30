begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.dev');

insert into news_sources (id, user_id, name, section, feed_url) values
  ('00000000-0000-0000-0000-0000000000a1', null, 'Teste', 'Geral', 'https://teste.dev/a.xml'),
  ('00000000-0000-0000-0000-0000000000a2', null, 'Outro', 'Geral', 'https://teste.dev/b.xml');

insert into news_items (user_id, source_id, url, title, summary, published_at) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-0000000000a1', 'https://t.dev/1', 'Nova IA do Google chega ao Brasil', '', now() - interval '1 hour'),
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-0000000000a1', 'https://t.dev/2', 'Dia de chuva em São Paulo', 'mídia relata alagamentos', now() - interval '2 hours'),
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-0000000000a1', 'https://t.dev/3', 'BBB 26: paredão', '', now() - interval '3 hours'),
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-0000000000a1', 'https://t.dev/4', 'ELEICAO municipal', '', now() - interval '4 hours'),
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-0000000000a1', 'https://t.dev/5', 'Notícia velha', '', now() - interval '5 days'),
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-0000000000a2', 'https://t.dev/6', 'Fonte não assinada', '', now() - interval '1 hour');

-- Usuário A
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
insert into news_subscriptions (source_id) values ('00000000-0000-0000-0000-0000000000a1');
insert into news_prefs (keywords, blocked, max_age_hours) values (array['IA', 'eleição'], array['bbb'], 48);

select is((select count(*) from news_feed())::int, 3,
  'só itens assinados, dentro da janela e não bloqueados');
select ok((select highlighted from news_feed() where url = 'https://t.dev/1'),
  '"IA" destaca "Nova IA do Google"');
select ok(not (select highlighted from news_feed() where url = 'https://t.dev/2'),
  '"IA" não destaca "Dia" nem "mídia"');
select ok((select highlighted from news_feed() where url = 'https://t.dev/4'),
  '"eleição" destaca "ELEICAO"');
select results_eq(
  'select url from news_feed()',
  $$ values ('https://t.dev/1'), ('https://t.dev/4'), ('https://t.dev/2') $$,
  'destaques primeiro, depois os mais recentes');
select lives_ok(
  $$ insert into news_sources (user_id, name, feed_url) values ('11111111-1111-1111-1111-111111111111', 'Meu blog', 'https://blog.dev/feed') $$,
  'A adiciona um feed próprio');
select throws_ok(
  $$ insert into news_sources (user_id, name, feed_url) values (null, 'Falso catálogo', 'https://x.dev/f') $$,
  '42501', null,
  'usuário não escreve no catálogo');

-- Usuário B
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
select is((select count(*) from news_feed())::int, 0, 'B não vê as notícias de A');
select is((select count(*) from news_sources where name = 'Meu blog')::int, 0, 'B não vê o feed próprio de A');

select is((select count(*) from news_sources where user_id is null and name <> 'Teste' and name <> 'Outro')::int, 18, 'catálogo tem 18 fontes');

select * from finish();
rollback;
