-- Salvamento local primeiro: o app grava no aparelho e envia depois, então duas alterações da mesma linha
-- podem chegar fora de ordem. `client_updated_at` é o momento em que o aparelho fez a alteração; o gatilho
-- deixa valer a mais recente (último a alterar ganha), mesmo que ela chegue primeiro.
--   * update que não muda o campo (ponte da Alexa, MCP, SQL, funções do banco) → carimba now();
--   * update com carimbo MAIS VELHO que o gravado → ignorado por inteiro (a linha fica como está);
--   * senão → segue normalmente.

create or replace function public.client_updated_at_lww()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.client_updated_at is not distinct from old.client_updated_at then
    new.client_updated_at := now();
  elsif new.client_updated_at < old.client_updated_at then
    return old;
  end if;
  return new;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array['spaces', 'notes', 'tasks', 'events', 'event_tags', 'workouts', 'workout_exercises',
                           'workout_sessions', 'set_logs', 'shopping_lists', 'shopping_items', 'user_settings',
                           'wake_plans', 'wake_overrides']
  loop
    execute format(
      'alter table public.%I add column client_updated_at timestamptz not null default now()', t);
    -- Prefixo "z_": roda depois do touch_updated_at (ordem alfabética), assim `return old` desfaz também o
    -- updated_at e uma atualização ignorada não mexe em nada.
    execute format(
      'create trigger z_client_updated_at before update on public.%I for each row execute function public.client_updated_at_lww()',
      t);
    -- Todas já entraram na publicação realtime nas migrações anteriores; só completa se alguma faltar.
    if not exists (select 1 from pg_publication_tables
                    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
