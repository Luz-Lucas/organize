-- Excluir uma pasta (espaço) nunca apaga cadernos.
--
-- `notes.space_id` é `on delete cascade`: apagar o espaço apagava todas as notas dele, inclusive
-- os cadernos (e, em cascata, as páginas). Agora, antes de apagar o espaço, os cadernos dele
-- ficam sem espaço ("Sem pasta"). Notas de texto e tarefas seguem a regra antiga.
-- Excluir a conta continua apagando tudo (cascata por `user_id`).
create or replace function public.spaces_keep_notebooks()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  update public.notes
     set space_id = null
   where space_id = old.id
     and kind = 'notebook';
  return old;
end;
$$;

create trigger spaces_keep_notebooks
  before delete on public.spaces
  for each row execute function public.spaces_keep_notebooks();
