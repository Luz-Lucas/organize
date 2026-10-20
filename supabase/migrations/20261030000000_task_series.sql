-- Séries de tarefas (mesmo modelo das séries de eventos): cada ocorrência é uma
-- linha de `tasks` com o próprio `due_at`; o `series_id` agrupa as da mesma série
-- e `recurrence` guarda (só para informação) a regra usada para gerá-las.
-- {"freq":"daily|weekdays|weekly|biweekly|monthly","days":[1..7],"until":"YYYY-MM-DD"|null,"count":int|null}

alter table public.tasks
  add column series_id uuid,
  add column recurrence jsonb check (recurrence is null or jsonb_typeof(recurrence) = 'object');

create index tasks_series_idx on public.tasks (user_id, series_id, due_at) where series_id is not null;
