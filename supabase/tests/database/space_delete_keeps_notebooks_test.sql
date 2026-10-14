begin;
create extension if not exists pgtap with schema extensions;
select plan(5);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev');

insert into spaces (id, user_id, name, kind) values
  ('5a000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Cálculo', 'materia'),
  ('5a000000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'Outra', 'geral');
insert into notes (id, user_id, space_id, title, kind) values
  ('c0000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', '5a000000-0000-0000-0000-000000000001', 'Caderno de Cálculo', 'notebook'),
  ('c0000000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', '5a000000-0000-0000-0000-000000000001', 'Nota de Cálculo', 'text'),
  ('c0000000-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', '5a000000-0000-0000-0000-000000000002', 'Caderno de Outra', 'notebook');
insert into note_pages (id, user_id, note_id, idx) values
  ('d0000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'c0000000-0000-0000-0000-000000000001', 0);

delete from spaces where id = '5a000000-0000-0000-0000-000000000001';

select is((select count(*)::int from notes where id = 'c0000000-0000-0000-0000-000000000001'), 1,
  'o caderno sobrevive à exclusão do espaço');
select is((select space_id from notes where id = 'c0000000-0000-0000-0000-000000000001'), null,
  'o caderno fica sem espaço');
select is((select count(*)::int from note_pages where note_id = 'c0000000-0000-0000-0000-000000000001'), 1,
  'as páginas do caderno sobrevivem');
select is((select count(*)::int from notes where id = 'c0000000-0000-0000-0000-000000000002'), 0,
  'a nota de texto do espaço continua sendo apagada em cascata (regra antiga)');
select is((select space_id::text from notes where id = 'c0000000-0000-0000-0000-000000000003'),
  '5a000000-0000-0000-0000-000000000002', 'cadernos de outros espaços não são tocados');

select * from finish();
rollback;
