-- Prioridade das tarefas: baixa, média (padrão) ou alta.
alter table public.tasks
  add column priority text not null default 'media'
  constraint tasks_priority_check check (priority in ('baixa', 'media', 'alta'));
