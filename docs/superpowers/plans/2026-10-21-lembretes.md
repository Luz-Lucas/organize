# Lembretes (celular + Alexa) — Plano

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:test-driven-development. Cada agente faz só a sua Task, sem commit.

**Goal:** lembretes de tarefas e eventos no celular (notificação local) e na Alexa (a ponte fala no Echo).

## Design aprovado pelo usuário (2026-10-21)
- Opções por item: **1 dia (1440), 1 hora (60), 30 min (30), 15 min (15)** antes — várias ao mesmo tempo.
- Padrão: **tarefa = {60}**, **evento = {30}** (inclusive academia/etiqueta secundária e séries). Vale para o que já existe.
- **Tarefa só com data** (prazo às 23:59 local — é como o app grava "sem hora"): ignora os minutos; avisa às **10:00 do dia do prazo
  só se prioridade = `alta`**; senão não avisa. Tarefa concluída ou sem prazo: não avisa.
- **Evento de dia inteiro:** não avisa.
- **Não perturbe** (Ajustes, por conta): ligado por padrão, **23:00 → 10:00** (atravessa a meia-noite). Lembrete que cairia dentro do
  intervalo vai para o fim do intervalo (10:00) **se** isso ainda for antes do horário do item; senão é descartado. Dois lembretes
  que caem no mesmo instante viram um.
- **Celular (Android):** notificação local agendada; título = título do item; corpo: evento "Começa às 15:00" (ou "Amanhã às 15:00"),
  tarefa "Prazo às 18:00" / tarefa só com data "Vence hoje". Tarefa tem botão **Concluir**; tocar abre `/tarefas` ou `/agenda`.
- **Alexa:** a ponte fala no Echo escolhido em Ajustes: "Lembrete: reunião com o Pedro às 15 horas." / "Lembrete: hoje vence a tarefa
  pagar a luz." — **só se a presença não for `away`** (usa `presence.ts`). Mesmo não perturbe.
- Ajustes → "Lembretes": chave Celular, chave Alexa + escolha do Echo (lista de `alexa_devices` tipo Echo), não perturbe (chave + início + fim).
- Editores de tarefa e evento: "Lembrar" com 4 chips (multi), pré-marcados com o padrão; em tarefa só com data mostra a dica
  "Tarefas sem horário avisam às 10h se forem de prioridade alta".

## Contrato de dados — Task A cria; todos usam
Migração `supabase/migrations/20261031000000_reminders.sql`:
- `tasks.reminders smallint[] not null default '{60}'`, `events.reminders smallint[] not null default '{30}'`; check: cada valor em
  (1440, 60, 30, 15) e sem repetidos (`reminders <@ '{1440,60,30,15}'`).
- `user_settings`: `reminders_phone boolean not null default true`, `reminders_alexa boolean not null default true`,
  `reminder_echo text null` (serial/id do Echo como em `alexa_devices`), `dnd_enabled boolean not null default true`,
  `dnd_start time not null default '23:00'`, `dnd_end time not null default '10:00'`.
- `reminder_deliveries(id uuid pk, user_id …, kind text check in ('task','event'), item_id uuid, fire_at timestamptz, channel text check in ('alexa'),
  created_at)`, único `(user_id, kind, item_id, fire_at, channel)`; RLS dono; só a ponte (service role) escreve.

## Algoritmo comum (Dart em `app/lib/reminders/reminder_times.dart`; TS em `bridge/src/reminders.ts` — mesmos casos de teste)
`reminderFires(items, settings, now, tz) → [{kind, itemId, title, fireAt, itemAt, dateOnly}]`:
1. tarefa: `status=='done'` ou `dueAt==null` → nada. Data-only (hora local == 23:59) → `prioridade=='alta'` ? `[dia do prazo 10:00 local]` : nada.
   Senão `dueAt − m` para cada m.  Evento: `allDay` → nada; senão `startsAt − m`.
2. não perturbe ligado e hora local de `fireAt` ∈ [start, end) (com volta da meia-noite) → `fireAt = próximo end` ; se `fireAt ≥ itemAt`, descarta
   (data-only usa `itemAt` = 23:59 do dia).
3. junta iguais (mesmo item + mesmo `fireAt`); remove `fireAt ≤ now`.
Casos de teste obrigatórios (fuso America/Sao_Paulo): evento 15:00 → 14:30; evento 08:30 com {30} → 08:00 cai no DND → 10:00 ≥ 08:30 → descartado;
evento 11:00 com {1440} → véspera 11:00; evento 10:20 com {60,30} → 09:20 e 09:50 viram 10:00 único; tarefa data-only alta → 10:00; data-only média → nada;
DND desligado → 08:00 mantém; DND 22:00→07:00 com aviso 23:30 → 07:00 do dia seguinte.

---

### Task A — Banco + MCP (Onda 1)
Migração + pgTAP `supabase/tests/database/reminders_test.sql` (defaults nos existentes, check de valores, RLS de `reminder_deliveries`, único).
MCP (`mcp/src/tools/tasks.ts`, `agenda.ts`): `reminders?: (1440|60|30|15)[]` em create/update de tarefa e evento; saída inclui `reminders`.
Verificar: `npx supabase migration up --local`, `npx supabase test db`, `cd mcp && npm test && npm run typecheck` (vars via `npx supabase status -o env`).

### Task B — Ponte/Alexa (Onda 1)
`bridge/src/reminders.ts` (algoritmo + textos falados) e laço em `bridge/src/main.ts` a cada 60 s: carrega tarefas não concluídas com prazo nas
próximas 48 h e eventos que começam nas próximas 26 h + `user_settings` + presença; para cada disparo com `fireAt ∈ (agora − 5 min, agora]`
e `reminders_alexa` ligado e `reminder_echo` definido e presença ≠ `away`: insere em `reminder_deliveries` (on conflict do nothing) e, se inseriu,
fala no Echo (`gateway.speak`, com `chunkSpeech`). Store em `supabase-store.ts`. Testes com fakes e (se houver) banco local.
Verificar: `cd bridge && npm test && npm run typecheck`.

### Task C1 — App: dados, editores e Ajustes (Onda 1)
`TaskItem.reminders` / `CalendarEvent.reminders` (`List<int>`, padrão [60]/[30], `fromMap/toMap/copyWith`, séries copiam);
`UserSettings`: `remindersPhone`, `remindersAlexa`, `reminderEcho`, `dndEnabled`, `dndStart`/`dndEnd` (minutos do dia ou `TimeOfDay`-like puro);
repositório de ajustes grava; chips "Lembrar" (widget reutilizável, ex. `app/lib/features/common/reminder_chips.dart`) em `task_dialog.dart` e
`event_dialog.dart`; cartão "Lembretes" em Ajustes (`app/lib/features/settings/reminders_card.dart`). Testes de widget e de mapa.
NÃO crie a lógica de agendamento (Task C2).

### Task C2 — App: notificações no celular (Onda 2, depois de C1)
`flutter_local_notifications` + `timezone` (+ `flutter_timezone` se preciso) no pubspec (versões compatíveis com Flutter 3.47 / AGP atuais;
desugaring se o plugin pedir); `AndroidManifest`: `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`/`USE_EXACT_ALARM`, `RECEIVE_BOOT_COMPLETED`
e os receivers do plugin. `app/lib/reminders/`: `reminder_times.dart` (algoritmo), `reminder_scheduler.dart` (interface `ReminderSink` +
implementação do plugin; cancela e reagenda tudo do horizonte de **3 dias**; ids estáveis por hash de kind+id+fireAt), `reminder_sync.dart`
(como `widget_sync.dart`: ouve tarefas, eventos e ajustes e reagenda com debounce; só Android e só com `remindersPhone`), pedido de permissão
na primeira vez (Android 13+) e quando o usuário liga a chave; reagendar também no workmanager periódico (`widget_background.dart`);
ação **Concluir** em segundo plano (callback top-level que inicializa o Supabase como `widget_shop_action.dart` e marca `status=done`,
`completed_at=now`); toque abre `/tarefas` ou `/agenda` (tratar no `main.dart`). Testes: algoritmo (casos acima), scheduler com sink falso, sync.
Verificar: suíte inteira UMA vez, `flutter analyze`, `flutter build apk --debug` UMA vez e `pkill -f '[G]radleDaemon'`.

## Global Constraints
- pt-BR; estilo do arquivo vizinho; nada de dado pessoal no repo (público). Sem nuvem/VM/commit.
- Flutter em `~/development/flutter/bin` (JAVA_HOME=$HOME/development/android-studio/jbr, ANDROID_HOME=$HOME/Android/Sdk). Pouca RAM:
  testes Dart por arquivo com `TZ=America/Sao_Paulo flutter test <arquivos> -j 2`; não rode `dart format` no projeto inteiro.
