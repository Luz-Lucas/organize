# Tarefas recorrentes — Plano

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:test-driven-development. Cada agente faz só a sua Task, sem commit.

**Goal:** tarefas que se repetem (ex.: "Lab de S01" toda terça até 1º/12), no mesmo modelo das séries de eventos.

**Design aprovado pelo usuário (2026-10-19):**
- Editor de tarefa ganha "Repetir" (mesmas opções/UI da agenda: `RepeatFreq` + dias da semana + fim por data ou nº de vezes). Exige prazo (a repetição parte do `dueAt`).
- Cada ocorrência é uma linha de `tasks` com o próprio `due_at`; mesmas `series_id` e `recurrence` (jsonb informativo, igual a `events`).
- **Lista de Tarefas (lista e quadro), "Para hoje" da Início e `list_tasks` do MCP mostram só a próxima pendente de cada série** = a ocorrência não concluída de menor `due_at`. Concluídas aparecem normalmente onde concluídas aparecem hoje.
- Selo 🔁 com o resumo ("Toda semana às ter, até 1 dez").
- Editar (título/descrição/prioridade/prazo/espaço) ou apagar ocorrência de série pergunta "só esta / esta e as seguintes / todas" (`showSeriesScopeDialog`). Marcar como feita não pergunta.
- **Widget Android: tarefas com `series_id` não aparecem.**
- MCP: `create_task` aceita `repeat` (mesmo formato do `create_event`); `update_task`/`delete_task` aceitam `scope` (`one`|`following`|`all`, padrão `one`).

## Global Constraints
- pt-BR, estilo dos arquivos vizinhos. Nada de dado pessoal no repo (público). Sem nuvem/VM/commit.
- Flutter em `~/development/flutter/bin`; pouca RAM: testes por arquivo com `TZ=America/Sao_Paulo flutter test <arquivos> -j 2`.

## Review Focus
1. Série criada com prazo no passado ou `until` antes do prazo → 0 ou 1 ocorrência, sem quebrar (mostra "Nenhuma ocorrência" como na agenda).
2. Ocorrência atrasada não concluída + próxima futura → a lista mostra a atrasada; concluída a atrasada, aparece a seguinte.
3. "Esta e as seguintes" a partir da 1ª ocorrência não cria série nova (igual a eventos).
4. Desmarcar uma concluída de série volta a ser a "próxima pendente" se for a mais antiga.
5. Série inteira concluída → nada dela na lista de pendentes, sem erro.

---

### Task A — Banco + MCP
**Files:** Create `supabase/migrations/20261030000000_task_series.sql` (`alter table tasks add column series_id uuid, add column recurrence jsonb check (...)` igual a `20261017000000_event_series.sql`; índice `(user_id, series_id, due_at) where series_id is not null`) e pgTAP `supabase/tests/database/task_series_test.sql`. Modify `mcp/src/tools/tasks.ts` (reuse `expandRepeat` de `recurrence.ts`; `taskOut` ganha `seriesId`, `recurrence`; `list_tasks` sem `status` filtra para a próxima pendente por série; `repeat` exige `dueAt`; `scope` em update/delete por `series_id` + `due_at`, como `agenda.ts`), testes em `mcp/test/`.
Verificar: `npx supabase migration up --local`, `npx supabase test db`, `cd mcp && npm test && npm run typecheck` (exporte `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY` via `npx supabase status -o env` para os testes de banco).

### Task B — App
**Files:** Modify `app/lib/domain/task_item.dart` (`seriesId`, `recurrence: Recurrence?`, `fromMap/toMap/copyWith` com `clearSeries`), `app/lib/domain/agenda.dart` ou novo `app/lib/domain/task_series.dart`, `app/lib/data/repository.dart` + `memory_repository.dart` + `supabase_repository.dart`, `app/lib/features/tasks/task_dialog.dart`, `tasks_screen.dart`, `kanban_board.dart`, `task_card.dart`, `app/lib/features/today/dashboard_data.dart` (`buildTodayPlan`), `app/lib/widgets/widget_snapshot.dart` (e `widget_background.dart` se filtrar lá). Extrair a seção "Repetir" de `event_dialog.dart` para um widget reutilizável (ex.: `app/lib/features/agenda/repeat_section.dart`) usado pelos dois diálogos, sem mudar o comportamento da agenda.

**Interfaces:**
- `List<TaskItem> nextPendingPerSeries(Iterable<TaskItem> tasks)` — mantém tarefas sem série e as concluídas; de cada série, só a não concluída de menor `dueAt`.
- `class TaskSeriesOps { static List<TaskItem> buildSeries(TaskItem template, Recurrence r, String Function() newId); static List<TaskItem> applyEdit(List<TaskItem> series, TaskItem target, TaskItem edited, SeriesScope scope, {String Function()? newSeriesId}); static List<String> deleteIds(List<TaskItem> series, TaskItem target, SeriesScope scope); }` — mesmas regras de `SeriesOps` (eventos), com `dueAt` no lugar de `startsAt` (deslocamento de dia/hora aplicado a todas no `all`/`following`; `one` tira a ocorrência da série; ocorrências concluídas mantêm o `status`).
- `Repository`: `Future<void> upsertTasks(List<TaskItem> tasks)`, `Future<void> deleteTasks(List<String> ids)`, `Future<List<TaskItem>> listTaskSeries(String seriesId)`.
- Testes: lógica (os 5 itens do Review Focus, `buildSeries` "toda ter até 1/12" a partir de ter 20/10/2026 → 7 ocorrências (20/10 … 1/12)), diálogo (criar série, editar com escopo, apagar com escopo), Tarefas mostra só a próxima, widget sem séries, Para hoje com a próxima. No fim: suíte inteira UMA vez (`--exclude-tags integration -j 2`) e `flutter analyze` limpo.
