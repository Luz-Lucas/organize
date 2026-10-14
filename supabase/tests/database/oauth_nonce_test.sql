begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

select has_table('public', 'oauth_state_nonces', 'tabela de nonces existe');
select has_function('public', 'consume_oauth_nonce', array['text'], 'função consume_oauth_nonce existe');

-- papel postgres: primeiro uso vale, repetição é recusada
select is(public.consume_oauth_nonce('nonce-1'), true, 'primeiro uso do nonce vale');
select is(public.consume_oauth_nonce('nonce-1'), false, 'segundo uso do mesmo nonce é recusado');
select is(public.consume_oauth_nonce('nonce-2'), true, 'outro nonce vale');

-- limpeza oportunista: nonces com mais de 1 dia somem na próxima chamada
update public.oauth_state_nonces set used_at = now() - interval '2 days' where nonce = 'nonce-1';
select is(public.consume_oauth_nonce('nonce-3'), true, 'novo nonce vale');
select is((select count(*) from public.oauth_state_nonces where nonce = 'nonce-1')::int, 0,
  'nonce com mais de 1 dia foi apagado');
select is((select count(*) from public.oauth_state_nonces where nonce in ('nonce-2', 'nonce-3'))::int, 2,
  'nonces recentes ficam');

select throws_ok($$ insert into public.oauth_state_nonces (nonce) values ('') $$, '23514', null,
  'nonce vazio é rejeitado');

-- anon e authenticated não enxergam nem usam nada
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
select throws_ok($$ select * from public.oauth_state_nonces $$, '42501', null, 'authenticated não lê a tabela');
select throws_ok($$ select public.consume_oauth_nonce('x') $$, '42501', null, 'authenticated não executa a função');
reset role;
set local role anon;
select throws_ok($$ insert into public.oauth_state_nonces (nonce) values ('y') $$, '42501', null, 'anon não escreve na tabela');
select throws_ok($$ select public.consume_oauth_nonce('y') $$, '42501', null, 'anon não executa a função');

select * from finish();
rollback;
