# Organizacional — Fase 3: Alexa — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pelo app, configurar despertares que tocam Spotify num Echo e falam o resumo do dia (aulas, tarefas, manchetes), executar rotinas da Alexa, controlar dispositivos inteligentes e falar texto no Echo; e ter a skill "Alexa, abre organizacional" para ouvir o resumo sob demanda.

**Architecture:** Uma ponte Node/TypeScript roda numa VPS (Docker + Caddy com HTTPS) e tem duas partes. (1) A **skill oficial** (ask-sdk) responde em `https://<domínio>/alexa` com o resumo do dia lido do Supabase. (2) A parte **não oficial** (`alexa-remote2`, login por cookie) executa comandos que o app grava na tabela `alexa_commands` e roda um agendador que transforma `wake_plans` em despertares. Cada despertar tem um **alarme reserva nativo** criado com antecedência no Echo e apagado quando a sequência dá certo. A lógica (agendador, resumo, comandos, skill) fica em módulos puros testados com vitest, com um gateway falso no lugar da Alexa.

**Tech Stack:** Node 22, TypeScript 5, vitest, `@supabase/supabase-js` 2, `alexa-remote2`, `ask-sdk-core`, `ask-sdk-express-adapter`, express, Docker, Caddy 2; Supabase (Postgres/RLS/Realtime); Flutter + Riverpod + go_router (Fases 1–2).

**Spec:** `docs/superpowers/specs/2026-09-28-organizacional-design.md`
**Pré-requisitos:** Fase 1 e Fase 2 concluídas. Este plano usa `touch_updated_at()`, as tabelas `events`/`tasks`, a função `news_feed` e `news_prefs.briefing_count`; no app, `RepositoryException`, `clockProvider`, `asyncView`, `SectionHeader`, `EmptyHint`, `showError`, `newId`, `parseDate`, `pumpApp`, `newsFeedProvider`, `NewsTile` e o router.

## Global Constraints

- Fuso de referência: `America/Sao_Paulo`. A ponte calcula horários **só** com `Intl` e o fuso explícito; o processo também roda com `TZ=America/Sao_Paulo`, porque o `alexa-remote2` monta os alarmes no horário local do processo. A ponte **se recusa a iniciar** se o fuso do processo divergir do configurado.
- Toda tabela nova tem `user_id` e RLS. O app só lê `alexa_devices`, `alexa_routines`, `alexa_bridge_status` e `wake_runs`; em `alexa_commands`, o app só insere com `status = 'pending'`; `wake_plans` é CRUD do dono. A ponte escreve com a service role, sempre filtrando por `ORGANIZACIONAL_USER_ID`.
- Comandos do app com mais de **120 s** sem execução são marcados `expired` e **não** são executados (ex.: não acender a luz horas depois).
- Um despertar dispara **no máximo uma vez** por plano e data (`wake_runs` único por `(plan_id, run_date)` + RPC `claim_wake_run`); a janela para disparar é de **15 min** após o horário.
- Alarme reserva: criado até **24 h** antes, para **10 min** depois do horário; apagado só se a sequência produzir áudio (música ou fala).
- Fala no Echo em blocos de até **240 caracteres**; o SSML da skill é escapado (`& < > " '`).
- Resumo: até 6 eventos e 5 tarefas por lista; a quantidade de manchetes vem de `news_prefs.briefing_count` (padrão 3).
- Skill privada: se `ALEXA_ALLOWED_USER_ID` não bater com o usuário da requisição, a skill responde "Esta skill é privada." A assinatura e o timestamp de cada requisição são verificados pelo `ExpressAdapter`.
- Segredos só no `.env` da VPS (fora do git): `SUPABASE_SERVICE_ROLE_KEY`, cookie da Amazon em `/data/alexa-cookie.json`.
- UI em pt-BR; testes do app com `TZ=America/Sao_Paulo`; `flutter analyze` sem erros nem warnings.

## Review Focus

1. **VPS em UTC:** um despertar às 22:30 de Brasília (01:30Z do dia seguinte) dispara na data local certa; um processo com fuso diferente do configurado não inicia. Testes `scheduler.test.ts` → "fronteira UTC" e `time.test.ts` → `timeZoneMatches` (Tasks 2–3).
2. **Ponte fora do ar ou reiniciando perto do horário:** o despertar dispara uma vez só (idempotente) e, se a ponte perdeu a janela, o alarme reserva toca e o run fica `missed`. Testes `scheduler.test.ts` (Task 3) e `supabase-store.test.ts` → "reivindica uma única vez" (Task 6).
3. **Spotify não vinculado ou busca sem resultado:** o resumo falado acontece mesmo assim e o alarme reserva é apagado; se nada tocar, o alarme reserva continua. Testes `wake.test.ts` (Task 4).
4. **Comando antigo na fila** (a ponte volta depois de horas): expira em vez de executar. Brilho fora de 0–100 falha com mensagem clara. Testes `commands.test.ts` (Task 4).
5. **Título de evento com `&` ou `<`** (ex.: "P&D <Lab>"): a skill responde SSML válido. Login da Alexa expirado: o app mostra o aviso em Hoje (se houver despertar ativo) e em Casa. Testes `skill.test.ts` (Task 5) e `alexa_test.dart`/`home_test.dart` (Tasks 8–9).

---

## Mapa de arquivos

```
supabase/
├── migrations/20260930000000_alexa.sql
└── tests/database/alexa_test.sql
bridge/
├── package.json, tsconfig.json, vitest.config.ts, .gitignore, .env.example
├── Dockerfile, docker-compose.yml, Caddyfile
├── skill/interaction-model.pt-BR.json
├── src/
│   ├── types/alexa-remote2.d.ts
│   ├── config.ts            loadConfig
│   ├── time.ts              tzOffsetMinutes, localParts, zonedTime, zonedDayRange, addDays, formatLongDate, formatTime, timeZoneMatches
│   ├── briefing.ts          buildBriefing, headlinesText, splitTasks, chunkSpeech, escapeSsml
│   ├── scheduler.ts         WakePlan, WakeRun, WakeAction, planWakeActions, occurrence
│   ├── gateway.ts           AlexaGateway, AlexaAuthError, DeviceAction, EchoDevice, SmartDevice, Routine
│   ├── commands.ts          Command, executeCommand, isExpired, CommandError
│   ├── wake.ts              runWake, applyWakeActions, WakeStore
│   ├── skill.ts             buildSkill
│   ├── supabase-store.ts    SupabaseStore
│   ├── alexa-remote-gateway.ts  AlexaRemoteGateway, mapSmartEntities, mapRoutines
│   ├── main.ts              liga tudo (servidor, loops)
│   └── scripts/login.ts, scripts/smoke.ts
└── test/
    ├── fake-gateway.ts
    ├── time.test.ts, briefing.test.ts, scheduler.test.ts, commands.test.ts, wake.test.ts,
    ├── skill.test.ts, config.test.ts, mappers.test.ts, supabase-store.test.ts
app/
├── lib/domain/alexa.dart
├── lib/data/alexa_repository.dart            AlexaRepository + runCommand
├── lib/data/memory_alexa_repository.dart
├── lib/data/supabase_alexa_repository.dart
├── lib/features/home/home_screen.dart         /casa
├── lib/features/home/wake_plan_screen.dart    /casa/despertar/:id ("novo" = criar)
├── lib/app/providers.dart, lib/app/router.dart (Modify)
├── lib/features/today/today_screen.dart, lib/main.dart, test/helpers.dart (Replace)
└── test/domain/alexa_test.dart, test/data/memory_alexa_repository_test.dart, test/features/home_test.dart
```

**Paralelização:** Task 1 ∥ Task 2 ∥ Task 8. Depois da 2: Task 3 ∥ Task 5. A Task 4 depende de 2 e 3. A Task 6 depende de 1–5. A Task 9 depende de 8. A Task 7 (deploy) fecha.

---

### Task 1: Schema da Alexa, RPCs de reivindicação e RLS

**Files:**
- Create: `supabase/migrations/20260930000000_alexa.sql`
- Test: `supabase/tests/database/alexa_test.sql`

**Interfaces:**
- Consumes: `public.touch_updated_at()` (Fase 1).
- Produces:
  - `wake_plans(id, user_id, label, days smallint[], time time, echo_device_id text, spotify_query text null, music_first bool, briefing_delay_min int, volume int, fallback_alarm bool, enabled bool, created_at, updated_at)`
  - `wake_runs(id, user_id, plan_id null, run_date date, planned_for timestamptz, status text ∈ armed|running|done|failed|missed|cancelled, fallback_handle text, note text, created_at, updated_at)`, único `(plan_id, run_date)`
  - `alexa_commands(id, user_id, kind ∈ device|routine|speak|music|sync|wake_test, payload jsonb, status ∈ pending|running|done|failed|expired, result text, created_at, started_at, finished_at)`
  - `alexa_devices(user_id, id text, name, kind ∈ echo|smart, operations text[], online bool, updated_at)`, pk `(user_id, id)`
  - `alexa_routines(user_id, id text, name, updated_at)`, pk `(user_id, id)`
  - `alexa_bridge_status(user_id pk, state ∈ ok|auth_required|error, message, last_seen)`
  - `claim_wake_run(p_user uuid, p_plan uuid, p_date date, p_planned timestamptz) → boolean`, `claim_command(p_id uuid) → boolean`

- [ ] **Step 1: Escrever o teste pgTAP**

Create `supabase/tests/database/alexa_test.sql`:
```sql
begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.dev');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select lives_ok(
  $$ insert into wake_plans (id, label, days, time, echo_device_id)
     values ('aaaaaaaa-0000-0000-0000-000000000001', 'Aula cedo', '{1,2,3,4,5}', '07:00', 'ECHO1') $$,
  'A cria um despertar');
select throws_ok(
  $$ insert into wake_plans (label, days, time, echo_device_id) values ('x', '{}', '07:00', 'E') $$,
  '23514', null, 'despertar sem dias é rejeitado');
select throws_ok(
  $$ insert into wake_plans (label, days, time, echo_device_id) values ('x', '{0,8}', '07:00', 'E') $$,
  '23514', null, 'dias fora de 1..7 são rejeitados');
select lives_ok(
  $$ insert into alexa_commands (kind, payload) values ('speak', '{"text":"oi","echoDeviceId":"ECHO1"}') $$,
  'A enfileira um comando');
select throws_ok(
  $$ insert into alexa_commands (kind, payload, status) values ('speak', '{}', 'done') $$,
  '42501', null, 'app não insere comando já concluído');

select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
select is((select count(*) from wake_plans)::int, 0, 'B não vê os despertares de A');

-- A ponte usa a service role (aqui: postgres, que ignora RLS)
reset role;
select ok(
  claim_wake_run('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000001', '2026-09-28', now()),
  'primeira reivindicação do despertar vence');
select ok(
  not claim_wake_run('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000001', '2026-09-28', now()),
  'segunda reivindicação no mesmo dia não dispara de novo');
select ok(claim_command((select id from alexa_commands limit 1)), 'primeira reivindicação do comando vence');
select ok(not claim_command((select id from alexa_commands limit 1)), 'comando não roda duas vezes');

select * from finish();
rollback;
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd /home/only/organizacional && npx supabase test db`
Expected: FAIL em `alexa_test.sql` (`relation "wake_plans" does not exist`).

- [ ] **Step 3: Escrever a migration**

Create `supabase/migrations/20260930000000_alexa.sql`:
```sql
create table public.wake_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  label text not null check (length(btrim(label)) > 0),
  days smallint[] not null check (cardinality(days) > 0 and days <@ array[1, 2, 3, 4, 5, 6, 7]::smallint[]),
  time time not null,
  echo_device_id text not null check (length(echo_device_id) > 0),
  spotify_query text,
  music_first boolean not null default true,
  briefing_delay_min integer not null default 3 check (briefing_delay_min between 0 and 30),
  volume integer not null default 30 check (volume between 0 and 100),
  fallback_alarm boolean not null default true,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.wake_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  plan_id uuid references public.wake_plans (id) on delete set null,
  run_date date not null,
  planned_for timestamptz not null,
  status text not null check (status in ('armed', 'running', 'done', 'failed', 'missed', 'cancelled')),
  fallback_handle text,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (plan_id, run_date)
);

create table public.alexa_commands (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  kind text not null check (kind in ('device', 'routine', 'speak', 'music', 'sync', 'wake_test')),
  payload jsonb not null default '{}',
  status text not null default 'pending' check (status in ('pending', 'running', 'done', 'failed', 'expired')),
  result text,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz
);
create index alexa_commands_pending_idx on public.alexa_commands (user_id, created_at) where status = 'pending';

create table public.alexa_devices (
  user_id uuid not null references auth.users (id) on delete cascade,
  id text not null,
  name text not null,
  kind text not null check (kind in ('echo', 'smart')),
  operations text[] not null default '{}',
  online boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

create table public.alexa_routines (
  user_id uuid not null references auth.users (id) on delete cascade,
  id text not null,
  name text not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

create table public.alexa_bridge_status (
  user_id uuid primary key references auth.users (id) on delete cascade,
  state text not null check (state in ('ok', 'auth_required', 'error')),
  message text,
  last_seen timestamptz not null default now()
);

create trigger touch_updated_at before update on public.wake_plans
  for each row execute function public.touch_updated_at();
create trigger touch_updated_at before update on public.wake_runs
  for each row execute function public.touch_updated_at();

alter table public.wake_plans enable row level security;
alter table public.wake_runs enable row level security;
alter table public.alexa_commands enable row level security;
alter table public.alexa_devices enable row level security;
alter table public.alexa_routines enable row level security;
alter table public.alexa_bridge_status enable row level security;

create policy "dono" on public.wake_plans for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "lê próprio" on public.wake_runs for select to authenticated
  using (user_id = (select auth.uid()));
create policy "lê próprio" on public.alexa_commands for select to authenticated
  using (user_id = (select auth.uid()));
create policy "enfileira próprio" on public.alexa_commands for insert to authenticated
  with check (user_id = (select auth.uid()) and status = 'pending');
create policy "lê próprio" on public.alexa_devices for select to authenticated
  using (user_id = (select auth.uid()));
create policy "lê próprio" on public.alexa_routines for select to authenticated
  using (user_id = (select auth.uid()));
create policy "lê próprio" on public.alexa_bridge_status for select to authenticated
  using (user_id = (select auth.uid()));

create or replace function public.claim_wake_run(p_user uuid, p_plan uuid, p_date date, p_planned timestamptz)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  affected integer;
begin
  insert into public.wake_runs (user_id, plan_id, run_date, planned_for, status)
  values (p_user, p_plan, p_date, p_planned, 'running')
  on conflict (plan_id, run_date) do update
    set status = 'running'
    where public.wake_runs.status in ('armed', 'cancelled');
  get diagnostics affected = row_count;
  return affected > 0;
end;
$$;

create or replace function public.claim_command(p_id uuid)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  affected integer;
begin
  update public.alexa_commands set status = 'running', started_at = now()
  where id = p_id and status = 'pending';
  get diagnostics affected = row_count;
  return affected > 0;
end;
$$;

alter publication supabase_realtime add table
  public.wake_plans, public.alexa_commands, public.alexa_devices,
  public.alexa_routines, public.alexa_bridge_status;
```

- [ ] **Step 4: Aplicar e rodar os testes**

Run: `npx supabase db reset && npx supabase test db`
Expected: PASS em `core_test.sql`, `news_test.sql` e `alexa_test.sql` (10).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260930000000_alexa.sql supabase/tests/database/alexa_test.sql
git commit -m "feat: schema da Alexa com despertares idempotentes e fila de comandos"
```

---

### Task 2: Projeto da ponte, fuso horário, config e texto do resumo

**Files:**
- Create: `bridge/package.json`, `bridge/tsconfig.json`, `bridge/vitest.config.ts`, `bridge/.gitignore`, `bridge/src/types/alexa-remote2.d.ts`
- Create: `bridge/src/time.ts`, `bridge/src/config.ts`, `bridge/src/briefing.ts`
- Test: `bridge/test/time.test.ts`, `bridge/test/config.test.ts`, `bridge/test/briefing.test.ts`

**Interfaces:**
- Consumes: nada.
- Produces:
  - `tzOffsetMinutes(at: Date, timeZone: string): number`
  - `localParts(at: Date, timeZone: string): { date: string /* YYYY-MM-DD */; weekday: number /* 1=seg..7=dom */; minutes: number /* desde 00:00 */ }`
  - `zonedTime(date: string, hhmm: string, timeZone: string): Date`, `zonedDayRange(now: Date, timeZone: string): { start: Date; end: Date }`, `addDays(date: string, n: number): string`
  - `formatLongDate(at: Date, timeZone: string): string` (ex.: `segunda-feira, 28 de setembro`), `formatTime(at: Date, timeZone: string): string` (ex.: `08:00`)
  - `timeZoneMatches(now: Date, timeZone: string, processOffsetMinutes?: number): boolean`
  - `interface Config { supabaseUrl; serviceKey; userId; timeZone; port: number; allowedAlexaUserId: string | null; cookieFile; amazonPage; alexaServiceHost; loginProxyPort: number }`, `loadConfig(env): Config`
  - `interface BriefingEvent { title: string; startsAt: Date; endsAt: Date; allDay: boolean; location: string | null }`, `interface BriefingTask { title: string }`, `interface BriefingNews { title: string; source: string }`, `interface BriefingInput { now: Date; timeZone: string; events: BriefingEvent[]; overdue: BriefingTask[]; dueToday: BriefingTask[]; news: BriefingNews[] }`
  - `buildBriefing(input: BriefingInput): string`, `headlinesText(news: BriefingNews[]): string`, `splitTasks(tasks: { title: string; dueAt: Date }[], dayStart: Date): { overdue: BriefingTask[]; dueToday: BriefingTask[] }`, `chunkSpeech(text: string, max?: number): string[]`, `escapeSsml(text: string): string`

- [ ] **Step 1: Criar o projeto**

Run:
```bash
mkdir -p /home/only/organizacional/bridge && cd /home/only/organizacional/bridge
npm init -y
npm install @supabase/supabase-js alexa-remote2 ask-sdk-core ask-sdk-model ask-sdk-express-adapter express
npm install -D typescript vitest tsx @types/node @types/express
mkdir -p src/types src/scripts test skill
```

Replace all of `bridge/package.json` keeping the `dependencies`/`devDependencies` blocks that npm generated, and set the rest to:
```json
{
  "name": "organizacional-bridge",
  "private": true,
  "type": "module",
  "engines": { "node": ">=22" },
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "start": "node dist/main.js",
    "test": "vitest run",
    "login": "node dist/scripts/login.js",
    "smoke": "node dist/scripts/smoke.js"
  }
}
```

Create `bridge/tsconfig.json`:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  },
  "include": ["src"]
}
```

Create `bridge/vitest.config.ts`:
```ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    env: { TZ: 'UTC' }, // simula a VPS: a lógica não pode depender do fuso da máquina
  },
});
```

Create `bridge/.gitignore`:
```
node_modules/
dist/
.env
data/
```

Create `bridge/src/types/alexa-remote2.d.ts`:
```ts
declare module 'alexa-remote2';
```

- [ ] **Step 2: Escrever os testes**

Create `bridge/test/time.test.ts`:
```ts
import { describe, expect, it } from 'vitest';
import {
  addDays, formatLongDate, formatTime, localParts, timeZoneMatches, tzOffsetMinutes, zonedDayRange, zonedTime,
} from '../src/time.js';

const SP = 'America/Sao_Paulo';

describe('time', () => {
  it('offset de São Paulo é -180 min', () => {
    expect(tzOffsetMinutes(new Date('2026-09-28T12:00:00Z'), SP)).toBe(-180);
  });

  it('localParts usa o fuso, não o do processo', () => {
    expect(localParts(new Date('2026-09-29T01:30:00Z'), SP)).toEqual({ date: '2026-09-28', weekday: 1, minutes: 22 * 60 + 30 });
    expect(localParts(new Date('2026-10-04T15:00:00Z'), SP).weekday).toBe(7);
  });

  it('zonedTime converte horário local em instante', () => {
    expect(zonedTime('2026-09-28', '07:00', SP).toISOString()).toBe('2026-09-28T10:00:00.000Z');
    expect(zonedTime('2026-09-28', '22:30', SP).toISOString()).toBe('2026-09-29T01:30:00.000Z');
  });

  it('zonedDayRange cobre o dia local inteiro', () => {
    const { start, end } = zonedDayRange(new Date('2026-09-29T02:00:00Z'), SP);
    expect(start.toISOString()).toBe('2026-09-28T03:00:00.000Z');
    expect(end.toISOString()).toBe('2026-09-29T03:00:00.000Z');
  });

  it('addDays atravessa mês', () => {
    expect(addDays('2026-09-30', 1)).toBe('2026-10-01');
    expect(addDays('2026-10-01', -1)).toBe('2026-09-30');
  });

  it('formatos em pt-BR', () => {
    const at = new Date('2026-09-28T11:05:00Z');
    expect(formatLongDate(at, SP)).toBe('segunda-feira, 28 de setembro');
    expect(formatTime(at, SP)).toBe('08:05');
  });

  it('timeZoneMatches compara com o offset do processo', () => {
    const now = new Date('2026-09-28T12:00:00Z');
    expect(timeZoneMatches(now, SP, -180)).toBe(true);
    expect(timeZoneMatches(now, SP, 0)).toBe(false);
  });
});
```

Create `bridge/test/config.test.ts`:
```ts
import { describe, expect, it } from 'vitest';
import { loadConfig } from '../src/config.js';

const base = {
  SUPABASE_URL: 'https://x.supabase.co',
  SUPABASE_SERVICE_ROLE_KEY: 'k',
  ORGANIZACIONAL_USER_ID: 'u',
};

describe('loadConfig', () => {
  it('aplica os padrões do Brasil', () => {
    const cfg = loadConfig(base);
    expect(cfg.timeZone).toBe('America/Sao_Paulo');
    expect(cfg.amazonPage).toBe('amazon.com.br');
    expect(cfg.alexaServiceHost).toBe('alexa.amazon.com.br');
    expect(cfg.port).toBe(8080);
    expect(cfg.allowedAlexaUserId).toBeNull();
    expect(cfg.cookieFile).toBe('/data/alexa-cookie.json');
  });

  it('falha com mensagem clara quando falta variável', () => {
    expect(() => loadConfig({ ...base, SUPABASE_SERVICE_ROLE_KEY: ' ' })).toThrow(
      'variável SUPABASE_SERVICE_ROLE_KEY obrigatória',
    );
  });
});
```

Create `bridge/test/briefing.test.ts`:
```ts
import { describe, expect, it } from 'vitest';
import { buildBriefing, chunkSpeech, escapeSsml, headlinesText, splitTasks, type BriefingInput } from '../src/briefing.js';

const SP = 'America/Sao_Paulo';
const now = new Date('2026-09-28T10:00:00Z'); // 07:00 em SP, segunda

const input = (over: Partial<BriefingInput> = {}): BriefingInput => ({
  now, timeZone: SP, events: [], overdue: [], dueToday: [], news: [], ...over,
});

describe('buildBriefing', () => {
  it('dia completo', () => {
    const text = buildBriefing(input({
      events: [
        { title: 'Cálculo I', startsAt: new Date('2026-09-28T11:00:00Z'), endsAt: new Date('2026-09-28T12:40:00Z'), allDay: false, location: 'Sala 12' },
        { title: 'Feriado acadêmico', startsAt: new Date('2026-09-28T03:00:00Z'), endsAt: new Date('2026-09-29T03:00:00Z'), allDay: true, location: null },
      ],
      dueToday: [{ title: 'Lista 3.' }],
      overdue: [{ title: 'Resumo' }, { title: 'Relatório' }],
      news: [{ source: 'G1', title: 'Chuva forte em BH.' }],
    }));
    expect(text).toBe(
      'Bom dia! Hoje é segunda-feira, 28 de setembro. ' +
      'Você tem 2 compromissos: às 08:00, Cálculo I, em Sala 12; o dia todo, Feriado acadêmico. ' +
      'Para hoje: Lista 3. ' +
      'Atenção, há 2 tarefas atrasadas: Resumo e Relatório. ' +
      'Manchetes: G1: Chuva forte em BH.',
    );
  });

  it('dia livre', () => {
    expect(buildBriefing(input())).toBe(
      'Bom dia! Hoje é segunda-feira, 28 de setembro. Sua agenda de hoje está livre. Nenhuma tarefa com prazo para hoje.',
    );
  });

  it('saudação segue o horário local, não o UTC', () => {
    expect(buildBriefing(input({ now: new Date('2026-09-28T17:00:00Z') }))).toMatch(/^Boa tarde!/);
    expect(buildBriefing(input({ now: new Date('2026-09-29T00:30:00Z') }))).toMatch(/^Boa noite! Hoje é segunda-feira/);
  });

  it('limita a quantidade de eventos e tarefas', () => {
    const ev = (i: number) => ({ title: `E${i}`, startsAt: new Date(`2026-09-28T1${i}:00:00Z`), endsAt: new Date(`2026-09-28T1${i}:30:00Z`), allDay: false, location: null });
    const text = buildBriefing(input({
      events: [0, 1, 2, 3, 4, 5, 6, 7].map(ev),
      dueToday: ['a', 'b', 'c', 'd', 'e', 'f', 'g'].map((title) => ({ title })),
    }));
    expect(text).toContain('Você tem 8 compromissos:');
    expect(text).toContain('; e mais 2.');
    expect(text).toContain('Para hoje: a, b, c, d e e, e mais 2.');
  });
});

describe('auxiliares', () => {
  it('headlinesText sem manchetes', () => {
    expect(headlinesText([])).toBe('Não encontrei manchetes das suas fontes agora.');
  });

  it('splitTasks separa atrasadas de hoje', () => {
    const start = new Date('2026-09-28T03:00:00Z');
    const r = splitTasks([
      { title: 'velha', dueAt: new Date('2026-09-28T02:59:00Z') },
      { title: 'hoje', dueAt: new Date('2026-09-28T03:00:00Z') },
    ], start);
    expect(r.overdue.map((t) => t.title)).toEqual(['velha']);
    expect(r.dueToday.map((t) => t.title)).toEqual(['hoje']);
  });

  it('chunkSpeech respeita o limite e não corta palavras', () => {
    const text = 'Frase um. ' + 'palavra '.repeat(60) + 'fim.';
    const chunks = chunkSpeech(text, 100);
    expect(chunks.every((c) => c.length <= 100)).toBe(true);
    expect(chunks.join(' ').replace(/\s+/g, ' ')).toBe(text.replace(/\s+/g, ' ').trim());
    expect(chunkSpeech('curto')).toEqual(['curto']);
  });

  it('escapeSsml', () => {
    expect(escapeSsml(`P&D <Lab> "x" 'y'`)).toBe('P&amp;D &lt;Lab&gt; &quot;x&quot; &apos;y&apos;');
  });
});
```

- [ ] **Step 3: Rodar e ver falhar**

Run: `npx vitest run`
Expected: FAIL (módulos `src/*.ts` não existem).

- [ ] **Step 4: Implementar**

Create `bridge/src/time.ts`:
```ts
const partsFormatter = new Map<string, Intl.DateTimeFormat>();

function formatterFor(timeZone: string): Intl.DateTimeFormat {
  let f = partsFormatter.get(timeZone);
  if (!f) {
    f = new Intl.DateTimeFormat('en-US', {
      timeZone, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', second: '2-digit',
    });
    partsFormatter.set(timeZone, f);
  }
  return f;
}

export function tzOffsetMinutes(at: Date, timeZone: string): number {
  const parts = formatterFor(timeZone).formatToParts(at);
  const get = (type: string) => Number(parts.find((p) => p.type === type)!.value);
  const asUtc = Date.UTC(get('year'), get('month') - 1, get('day'), get('hour'), get('minute'), get('second'));
  return Math.round((asUtc - Math.floor(at.getTime() / 1000) * 1000) / 60000);
}

export function localParts(at: Date, timeZone: string): { date: string; weekday: number; minutes: number } {
  const local = new Date(at.getTime() + tzOffsetMinutes(at, timeZone) * 60000);
  return {
    date: local.toISOString().slice(0, 10),
    weekday: ((local.getUTCDay() + 6) % 7) + 1,
    minutes: local.getUTCHours() * 60 + local.getUTCMinutes(),
  };
}

export function zonedTime(date: string, hhmm: string, timeZone: string): Date {
  const [y, m, d] = date.split('-').map(Number);
  const [h, mi] = hhmm.split(':').map(Number);
  const guess = Date.UTC(y, m - 1, d, h, mi);
  const first = guess - tzOffsetMinutes(new Date(guess), timeZone) * 60000;
  return new Date(guess - tzOffsetMinutes(new Date(first), timeZone) * 60000);
}

export function addDays(date: string, n: number): string {
  const [y, m, d] = date.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}

export function zonedDayRange(now: Date, timeZone: string): { start: Date; end: Date } {
  const today = localParts(now, timeZone).date;
  return { start: zonedTime(today, '00:00', timeZone), end: zonedTime(addDays(today, 1), '00:00', timeZone) };
}

export function formatLongDate(at: Date, timeZone: string): string {
  return new Intl.DateTimeFormat('pt-BR', { timeZone, weekday: 'long', day: 'numeric', month: 'long' }).format(at);
}

export function formatTime(at: Date, timeZone: string): string {
  return new Intl.DateTimeFormat('pt-BR', { timeZone, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(at);
}

export function timeZoneMatches(
  now: Date,
  timeZone: string,
  processOffsetMinutes: number = -now.getTimezoneOffset(),
): boolean {
  return tzOffsetMinutes(now, timeZone) === processOffsetMinutes;
}
```

Create `bridge/src/config.ts`:
```ts
export interface Config {
  supabaseUrl: string;
  serviceKey: string;
  userId: string;
  timeZone: string;
  port: number;
  allowedAlexaUserId: string | null;
  cookieFile: string;
  amazonPage: string;
  alexaServiceHost: string;
  loginProxyPort: number;
}

export function loadConfig(env: Record<string, string | undefined>): Config {
  const need = (key: string) => {
    const v = env[key]?.trim();
    if (!v) throw new Error(`variável ${key} obrigatória`);
    return v;
  };
  const opt = (key: string, fallback: string) => env[key]?.trim() || fallback;
  return {
    supabaseUrl: need('SUPABASE_URL'),
    serviceKey: need('SUPABASE_SERVICE_ROLE_KEY'),
    userId: need('ORGANIZACIONAL_USER_ID'),
    timeZone: opt('TZ_NAME', 'America/Sao_Paulo'),
    port: Number(opt('PORT', '8080')),
    allowedAlexaUserId: env.ALEXA_ALLOWED_USER_ID?.trim() || null,
    cookieFile: opt('ALEXA_COOKIE_FILE', '/data/alexa-cookie.json'),
    amazonPage: opt('AMAZON_PAGE', 'amazon.com.br'),
    alexaServiceHost: opt('ALEXA_SERVICE_HOST', 'alexa.amazon.com.br'),
    loginProxyPort: Number(opt('LOGIN_PROXY_PORT', '3001')),
  };
}
```

Create `bridge/src/briefing.ts`:
```ts
import { formatLongDate, formatTime, localParts } from './time.js';

export interface BriefingEvent { title: string; startsAt: Date; endsAt: Date; allDay: boolean; location: string | null }
export interface BriefingTask { title: string }
export interface BriefingNews { title: string; source: string }
export interface BriefingInput {
  now: Date;
  timeZone: string;
  events: BriefingEvent[];
  overdue: BriefingTask[];
  dueToday: BriefingTask[];
  news: BriefingNews[];
}

const MAX_EVENTS = 6;
const MAX_TASKS = 5;

const clean = (s: string) => s.trim().replace(/[.!?;:]+$/, '');

function joinList(items: string[]): string {
  if (items.length <= 1) return items.join('');
  return `${items.slice(0, -1).join(', ')} e ${items[items.length - 1]}`;
}

function taskList(tasks: BriefingTask[]): string {
  const shown = joinList(tasks.slice(0, MAX_TASKS).map((t) => clean(t.title)));
  return tasks.length > MAX_TASKS ? `${shown}, e mais ${tasks.length - MAX_TASKS}` : shown;
}

function greeting(now: Date, timeZone: string): string {
  const minutes = localParts(now, timeZone).minutes;
  return minutes < 12 * 60 ? 'Bom dia' : minutes < 18 * 60 ? 'Boa tarde' : 'Boa noite';
}

export function headlinesText(news: BriefingNews[]): string {
  if (news.length === 0) return 'Não encontrei manchetes das suas fontes agora.';
  return `Manchetes: ${news.map((n) => `${n.source}: ${clean(n.title)}`).join('. ')}.`;
}

export function buildBriefing(i: BriefingInput): string {
  const parts = [`${greeting(i.now, i.timeZone)}! Hoje é ${formatLongDate(i.now, i.timeZone)}.`];

  if (i.events.length === 0) {
    parts.push('Sua agenda de hoje está livre.');
  } else {
    const shown = i.events.slice(0, MAX_EVENTS).map((e) => {
      const when = e.allDay ? 'o dia todo' : `às ${formatTime(e.startsAt, i.timeZone)}`;
      return `${when}, ${clean(e.title)}${e.location ? `, em ${clean(e.location)}` : ''}`;
    });
    const n = i.events.length;
    const more = n > MAX_EVENTS ? `; e mais ${n - MAX_EVENTS}` : '';
    parts.push(`Você tem ${n === 1 ? '1 compromisso' : `${n} compromissos`}: ${shown.join('; ')}${more}.`);
  }

  parts.push(i.dueToday.length ? `Para hoje: ${taskList(i.dueToday)}.` : 'Nenhuma tarefa com prazo para hoje.');

  if (i.overdue.length) {
    const count = i.overdue.length === 1 ? 'há 1 tarefa atrasada' : `há ${i.overdue.length} tarefas atrasadas`;
    parts.push(`Atenção, ${count}: ${taskList(i.overdue)}.`);
  }

  if (i.news.length) parts.push(headlinesText(i.news));
  return parts.join(' ');
}

export function splitTasks(
  tasks: { title: string; dueAt: Date }[],
  dayStart: Date,
): { overdue: BriefingTask[]; dueToday: BriefingTask[] } {
  const overdue: BriefingTask[] = [];
  const dueToday: BriefingTask[] = [];
  for (const t of tasks) (t.dueAt < dayStart ? overdue : dueToday).push({ title: t.title });
  return { overdue, dueToday };
}

export function chunkSpeech(text: string, max = 240): string[] {
  const words = text.replace(/\s+/g, ' ').trim().split(' ');
  const chunks: string[] = [];
  let current = '';
  for (const word of words) {
    const candidate = current ? `${current} ${word}` : word;
    const sentenceBreak = /[.!?;]$/.test(current) && candidate.length > max * 0.6;
    if (candidate.length > max || sentenceBreak) {
      if (current) chunks.push(current);
      current = word.slice(0, max);
    } else {
      current = candidate;
    }
  }
  if (current) chunks.push(current);
  return chunks;
}

export function escapeSsml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}
```

- [ ] **Step 5: Rodar e ver passar**

Run: `npx vitest run && npx tsc -p tsconfig.json --noEmit`
Expected: todos os testes passam; `tsc` sem erros.

- [ ] **Step 6: Commit**

```bash
cd /home/only/organizacional
git add bridge
git commit -m "feat(ponte): projeto, fuso horário, config e texto do resumo do dia"
```

---

### Task 3: Agendador de despertares (puro)

**Files:**
- Create: `bridge/src/scheduler.ts`
- Test: `bridge/test/scheduler.test.ts`

**Interfaces:**
- Consumes: `localParts`, `zonedTime`, `addDays` (Task 2).
- Produces:
  - `interface WakePlan { id: string; label: string; days: number[]; time: string /* "HH:MM" ou "HH:MM:SS" */; echoDeviceId: string; spotifyQuery: string | null; musicFirst: boolean; briefingDelayMin: number; volume: number; fallbackAlarm: boolean; enabled: boolean }`
  - `type RunStatus = 'armed' | 'running' | 'done' | 'failed' | 'missed' | 'cancelled'`
  - `interface WakeRun { id: string; planId: string | null; runDate: string; plannedFor: Date; status: RunStatus; fallbackHandle: string | null }`
  - `type WakeAction = { type: 'arm'; plan; runDate; plannedFor; fallbackAt } | { type: 'rearm'; run; plan; plannedFor; fallbackAt } | { type: 'cancel'; run } | { type: 'miss'; run } | { type: 'fire'; plan; runDate; plannedFor; run: WakeRun | null }`
  - `occurrence(plan: WakePlan, runDate: string, timeZone: string): Date | null`
  - `planWakeActions(plans: WakePlan[], runs: WakeRun[], now: Date, timeZone: string, opts?: SchedulerOptions): WakeAction[]`, `DEFAULT_OPTIONS = { graceMin: 15, fallbackDelayMin: 10, armAheadHours: 24 }`

- [ ] **Step 1: Escrever os testes**

Create `bridge/test/scheduler.test.ts`:
```ts
import { describe, expect, it } from 'vitest';
import { planWakeActions, type WakePlan, type WakeRun } from '../src/scheduler.js';

const SP = 'America/Sao_Paulo';
const plan = (over: Partial<WakePlan> = {}): WakePlan => ({
  id: 'p1', label: 'Aula', days: [1, 2, 3, 4, 5], time: '07:00:00', echoDeviceId: 'ECHO',
  spotifyQuery: 'lofi', musicFirst: true, briefingDelayMin: 3, volume: 30,
  fallbackAlarm: true, enabled: true, ...over,
});
const run = (over: Partial<WakeRun> = {}): WakeRun => ({
  id: 'r1', planId: 'p1', runDate: '2026-09-28', plannedFor: new Date('2026-09-28T10:00:00Z'),
  status: 'armed', fallbackHandle: 'h1', ...over,
});
const at = (iso: string) => new Date(iso);
const types = (actions: { type: string }[]) => actions.map((a) => a.type);

describe('planWakeActions', () => {
  it('antes do horário arma o alarme reserva para 10 min depois', () => {
    const actions = planWakeActions([plan()], [], at('2026-09-28T09:59:30Z'), SP);
    expect(actions).toEqual([{
      type: 'arm', plan: plan(), runDate: '2026-09-28',
      plannedFor: at('2026-09-28T10:00:00Z'), fallbackAt: at('2026-09-28T10:10:00Z'),
    }]);
  });

  it('não arma de novo o que já está armado', () => {
    expect(planWakeActions([plan()], [run()], at('2026-09-28T09:59:30Z'), SP)).toEqual([]);
  });

  it('no horário dispara (com ou sem run armado) e já arma o reserva de amanhã', () => {
    const now = at('2026-09-28T10:00:20Z');
    const actions = planWakeActions([plan()], [run()], now, SP);
    expect(types(actions)).toEqual(['fire', 'arm']);
    expect(actions[0]).toEqual(
      { type: 'fire', plan: plan(), runDate: '2026-09-28', plannedFor: at('2026-09-28T10:00:00Z'), run: run() },
    );
    expect(actions[1]).toMatchObject({ type: 'arm', runDate: '2026-09-29' });
    const noFallback = plan({ fallbackAlarm: false });
    expect(types(planWakeActions([noFallback], [], now, SP))).toEqual(['fire']);
  });

  it('não dispara duas vezes (run já rodando ou concluído)', () => {
    const now = at('2026-09-28T10:05:00Z');
    expect(types(planWakeActions([plan()], [run({ status: 'running' })], now, SP))).not.toContain('fire');
    expect(types(planWakeActions([plan()], [run({ status: 'done' })], now, SP))).not.toContain('fire');
  });

  it('passada a janela de 15 min, run armado vira "miss" e nada dispara (só arma amanhã)', () => {
    const actions = planWakeActions([plan()], [run()], at('2026-09-28T10:16:00Z'), SP);
    expect(types(actions)).toEqual(['miss', 'arm']);
  });

  it('fim de semana não dispara plano de dias úteis', () => {
    expect(planWakeActions([plan({ fallbackAlarm: false })], [], at('2026-10-03T10:00:30Z'), SP)).toEqual([]);
  });

  it('plano desativado cancela o alarme reserva armado', () => {
    expect(types(planWakeActions([plan({ enabled: false })], [run()], at('2026-09-28T08:00:00Z'), SP))).toEqual(['cancel']);
  });

  it('plano apagado (planId nulo) cancela o alarme reserva', () => {
    expect(types(planWakeActions([], [run({ planId: null })], at('2026-09-28T08:00:00Z'), SP))).toEqual(['cancel']);
  });

  it('mudança de horário rearma o alarme reserva', () => {
    const actions = planWakeActions([plan({ time: '06:30' })], [run()], at('2026-09-28T08:00:00Z'), SP);
    expect(actions).toEqual([{
      type: 'rearm', run: run(), plan: plan({ time: '06:30' }),
      plannedFor: at('2026-09-28T09:30:00Z'), fallbackAt: at('2026-09-28T09:40:00Z'),
    }]);
  });

  it('fronteira UTC: 22:30 de Brasília dispara na data local certa', () => {
    const p = plan({ time: '22:30', fallbackAlarm: false });
    const actions = planWakeActions([p], [], at('2026-09-29T01:30:30Z'), SP);
    expect(actions).toEqual([{ type: 'fire', plan: p, runDate: '2026-09-28', plannedFor: at('2026-09-29T01:30:00Z'), run: null }]);
  });

  it('plano às 23:55 ainda dispara depois da meia-noite, dentro da janela', () => {
    const p = plan({ time: '23:55', days: [1], fallbackAlarm: false });
    const actions = planWakeActions([p], [], at('2026-09-29T03:05:00Z'), SP); // terça 00:05 local
    expect(actions).toEqual([{ type: 'fire', plan: p, runDate: '2026-09-28', plannedFor: at('2026-09-29T02:55:00Z'), run: null }]);
  });

  it('run cancelado pode ser rearmado e disparado', () => {
    const cancelled = run({ status: 'cancelled', fallbackHandle: null });
    expect(types(planWakeActions([plan()], [cancelled], at('2026-09-28T09:00:00Z'), SP))).toEqual(['arm']);
    expect(types(planWakeActions([plan()], [cancelled], at('2026-09-28T10:01:00Z'), SP))).toEqual(['fire', 'arm']);
  });
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd bridge && npx vitest run test/scheduler.test.ts`
Expected: FAIL (`scheduler.ts` não existe).

- [ ] **Step 3: Implementar**

Create `bridge/src/scheduler.ts`:
```ts
import { addDays, localParts, zonedTime } from './time.js';

export interface WakePlan {
  id: string;
  label: string;
  days: number[];
  time: string;
  echoDeviceId: string;
  spotifyQuery: string | null;
  musicFirst: boolean;
  briefingDelayMin: number;
  volume: number;
  fallbackAlarm: boolean;
  enabled: boolean;
}

export type RunStatus = 'armed' | 'running' | 'done' | 'failed' | 'missed' | 'cancelled';

export interface WakeRun {
  id: string;
  planId: string | null;
  runDate: string;
  plannedFor: Date;
  status: RunStatus;
  fallbackHandle: string | null;
}

export type WakeAction =
  | { type: 'arm'; plan: WakePlan; runDate: string; plannedFor: Date; fallbackAt: Date }
  | { type: 'rearm'; run: WakeRun; plan: WakePlan; plannedFor: Date; fallbackAt: Date }
  | { type: 'cancel'; run: WakeRun }
  | { type: 'miss'; run: WakeRun }
  | { type: 'fire'; plan: WakePlan; runDate: string; plannedFor: Date; run: WakeRun | null };

export interface SchedulerOptions { graceMin: number; fallbackDelayMin: number; armAheadHours: number }
export const DEFAULT_OPTIONS: SchedulerOptions = { graceMin: 15, fallbackDelayMin: 10, armAheadHours: 24 };

const MIN = 60_000;

export function occurrence(plan: WakePlan, runDate: string, timeZone: string): Date | null {
  const weekday = localParts(zonedTime(runDate, '12:00', timeZone), timeZone).weekday;
  return plan.days.includes(weekday) ? zonedTime(runDate, plan.time.slice(0, 5), timeZone) : null;
}

export function planWakeActions(
  plans: WakePlan[],
  runs: WakeRun[],
  now: Date,
  timeZone: string,
  opts: SchedulerOptions = DEFAULT_OPTIONS,
): WakeAction[] {
  const actions: WakeAction[] = [];
  const planById = new Map(plans.map((p) => [p.id, p]));
  const runByKey = new Map(runs.filter((r) => r.planId).map((r) => [`${r.planId}:${r.runDate}`, r]));
  const grace = opts.graceMin * MIN;
  const fallbackAt = (occ: Date) => new Date(occ.getTime() + opts.fallbackDelayMin * MIN);

  // 1) Manutenção dos alarmes reserva já armados
  for (const run of runs) {
    if (run.status !== 'armed') continue;
    const plan = run.planId ? planById.get(run.planId) : undefined;
    const occ = plan && plan.enabled && plan.fallbackAlarm ? occurrence(plan, run.runDate, timeZone) : null;
    if (!plan || !occ) {
      actions.push({ type: 'cancel', run });
      continue;
    }
    if (now.getTime() > occ.getTime() + grace) {
      actions.push({ type: 'miss', run });
      continue;
    }
    if (now.getTime() >= occ.getTime()) continue; // na janela: o disparo abaixo cuida
    if (occ.getTime() !== run.plannedFor.getTime()) {
      actions.push({ type: 'rearm', run, plan, plannedFor: occ, fallbackAt: fallbackAt(occ) });
    }
  }

  // 2) Disparos e novos alarmes reserva (ontem cobre planos perto da meia-noite)
  const today = localParts(now, timeZone).date;
  for (const plan of plans) {
    if (!plan.enabled) continue;
    for (const runDate of [addDays(today, -1), today, addDays(today, 1)]) {
      const occ = occurrence(plan, runDate, timeZone);
      if (!occ) continue;
      const run = runByKey.get(`${plan.id}:${runDate}`) ?? null;
      const delta = now.getTime() - occ.getTime();
      const claimable = !run || run.status === 'armed' || run.status === 'cancelled';
      if (delta >= 0 && delta <= grace) {
        if (claimable) actions.push({ type: 'fire', plan, runDate, plannedFor: occ, run });
      } else if (
        delta < 0 &&
        -delta <= opts.armAheadHours * 60 * MIN &&
        plan.fallbackAlarm &&
        (!run || run.status === 'cancelled')
      ) {
        actions.push({ type: 'arm', plan, runDate, plannedFor: occ, fallbackAt: fallbackAt(occ) });
      }
    }
  }
  return actions;
}
```

- [ ] **Step 4: Rodar e ver passar**

Run: `npx vitest run && npx tsc -p tsconfig.json --noEmit`
Expected: todos passam; `tsc` sem erros.

- [ ] **Step 5: Commit**

```bash
cd /home/only/organizacional
git add bridge/src/scheduler.ts bridge/test/scheduler.test.ts
git commit -m "feat(ponte): agendador de despertares com alarme reserva"
```

---

### Task 4: Gateway, comandos e execução do despertar

**Files:**
- Create: `bridge/src/gateway.ts`, `bridge/src/commands.ts`, `bridge/src/wake.ts`, `bridge/test/fake-gateway.ts`
- Test: `bridge/test/commands.test.ts`, `bridge/test/wake.test.ts`

**Interfaces:**
- Consumes: `chunkSpeech` (Task 2); `WakePlan`, `WakeRun`, `WakeAction`, `RunStatus` (Task 3).
- Produces:
  - `type DeviceAction = 'turnOn' | 'turnOff' | 'setBrightness'`; `interface EchoDevice { id: string; name: string; online: boolean }`; `interface SmartDevice { id: string; name: string; operations: string[] }`; `interface Routine { id: string; name: string }`; `class AlexaAuthError extends Error`
  - `interface AlexaGateway { listEchos(); listSmartDevices(); listRoutines(); runRoutine(routineId, echoDeviceId); deviceAction(entityId, action, brightness?); speak(echoDeviceId, text); setVolume(echoDeviceId, volume); playSpotify(echoDeviceId, query); createAlarm(echoDeviceId, at: Date, label): Promise<string>; deleteAlarm(handle: string) }` (tudo `Promise`)
  - `type CommandKind = 'device' | 'routine' | 'speak' | 'music' | 'sync' | 'wake_test'`; `interface Command { id: string; kind: CommandKind; payload: Record<string, unknown>; createdAt: Date }`; `class CommandError extends Error`; `COMMAND_MAX_AGE_MS = 120_000`; `isExpired(cmd, now, maxAgeMs?)`; `interface CommandDeps { gateway; sync(): Promise<void>; wakeTest(planId: string): Promise<string> }`; `executeCommand(cmd, deps): Promise<string>`
  - `interface WakeResult { ok: boolean; notes: string[] }`; `runWake(plan, briefing: string, gateway, sleep: (ms: number) => Promise<void>): Promise<WakeResult>`
  - `interface WakeStore { armRun(planId, runDate, plannedFor: Date, fallbackHandle: string); setRunStatus(runId, status: RunStatus, note?: string | null); claimRun(planId, runDate, plannedFor: Date): Promise<boolean>; finishRun(planId, runDate, status: 'done' | 'failed', note: string) }`
  - `interface WakeDeps { gateway; store: WakeStore; briefing(): Promise<string>; sleep(ms): Promise<void>; log(msg: string): void }`; `applyWakeActions(actions, deps, inFlight: Set<string>): Promise<Promise<void>[]>` (devolve os disparos em andamento)

- [ ] **Step 1: Gateway falso e testes**

Create `bridge/test/fake-gateway.ts`:
```ts
import type { AlexaGateway, DeviceAction } from '../src/gateway.js';

export class FakeGateway implements AlexaGateway {
  calls: string[] = [];
  failOn = new Set<string>();
  alarms = new Map<string, { echo: string; at: Date; label: string }>();
  private next = 1;

  private async record(name: string, detail: string): Promise<void> {
    this.calls.push(`${name}(${detail})`);
    if (this.failOn.has(name)) throw new Error(`${name} falhou`);
  }

  async listEchos() { return [{ id: 'ECHO', name: 'Echo do quarto', online: true }]; }
  async listSmartDevices() { return [{ id: 'luz1', name: 'Luz do quarto', operations: ['turnOn', 'turnOff', 'setBrightness'] }]; }
  async listRoutines() { return [{ id: 'r1', name: 'Boa noite' }]; }
  async runRoutine(routineId: string, echo: string) { await this.record('runRoutine', `${routineId},${echo}`); }
  async deviceAction(entityId: string, action: DeviceAction, brightness?: number) {
    await this.record('deviceAction', `${entityId},${action}${brightness === undefined ? '' : `,${brightness}`}`);
  }
  async speak(echo: string, text: string) { await this.record('speak', `${echo},${text}`); }
  async setVolume(echo: string, volume: number) { await this.record('setVolume', `${echo},${volume}`); }
  async playSpotify(echo: string, query: string) { await this.record('playSpotify', `${echo},${query}`); }
  async createAlarm(echo: string, at: Date, label: string) {
    await this.record('createAlarm', `${echo},${at.toISOString()},${label}`);
    const handle = `alarme-${this.next++}`;
    this.alarms.set(handle, { echo, at, label });
    return handle;
  }
  async deleteAlarm(handle: string) {
    await this.record('deleteAlarm', handle);
    this.alarms.delete(handle);
  }
}
```

Create `bridge/test/commands.test.ts`:
```ts
import { describe, expect, it } from 'vitest';
import { executeCommand, isExpired, type Command } from '../src/commands.js';
import { FakeGateway } from './fake-gateway.js';

const cmd = (kind: Command['kind'], payload: Record<string, unknown>, createdAt = new Date('2026-09-28T10:00:00Z')): Command =>
  ({ id: 'c1', kind, payload, createdAt });

function deps() {
  const gateway = new FakeGateway();
  let synced = 0;
  return {
    gateway,
    get synced() { return synced; },
    d: { gateway, sync: async () => { synced++; }, wakeTest: async (id: string) => `teste ${id}` },
  };
}

describe('executeCommand', () => {
  it('liga, desliga e ajusta brilho', async () => {
    const { gateway, d } = deps();
    await executeCommand(cmd('device', { entityId: 'luz1', action: 'turnOn' }), d);
    await executeCommand(cmd('device', { entityId: 'luz1', action: 'setBrightness', brightness: 40 }), d);
    expect(gateway.calls).toEqual(['deviceAction(luz1,turnOn)', 'deviceAction(luz1,setBrightness,40)']);
  });

  it('valida ação e brilho', async () => {
    const { d } = deps();
    await expect(executeCommand(cmd('device', { entityId: 'luz1', action: 'explodir' }), d)).rejects.toThrow('ação desconhecida: explodir');
    await expect(executeCommand(cmd('device', { entityId: 'luz1', action: 'setBrightness', brightness: 150 }), d)).rejects.toThrow('brilho deve ser de 0 a 100');
    await expect(executeCommand(cmd('routine', { routineId: 'r1' }), d)).rejects.toThrow('campo "echoDeviceId" ausente');
  });

  it('fala em blocos, roda rotina, toca Spotify, sincroniza e testa despertar', async () => {
    const h = deps();
    await executeCommand(cmd('speak', { echoDeviceId: 'ECHO', text: 'Olá. '.repeat(80) }), h.d);
    expect(h.gateway.calls.filter((c) => c.startsWith('speak')).length).toBeGreaterThan(1);
    await executeCommand(cmd('routine', { routineId: 'r1', echoDeviceId: 'ECHO' }), h.d);
    await executeCommand(cmd('music', { echoDeviceId: 'ECHO', query: 'lofi' }), h.d);
    await executeCommand(cmd('sync', {}), h.d);
    expect(await executeCommand(cmd('wake_test', { planId: 'p1' }), h.d)).toBe('teste p1');
    expect(h.gateway.calls).toContain('runRoutine(r1,ECHO)');
    expect(h.gateway.calls).toContain('playSpotify(ECHO,lofi)');
    expect(h.synced).toBe(1);
  });

  it('comando com mais de 120 s expira', () => {
    const c = cmd('speak', {}, new Date('2026-09-28T10:00:00Z'));
    expect(isExpired(c, new Date('2026-09-28T10:02:00Z'))).toBe(false);
    expect(isExpired(c, new Date('2026-09-28T10:02:01Z'))).toBe(true);
  });
});
```

Create `bridge/test/wake.test.ts`:
```ts
import { describe, expect, it } from 'vitest';
import { AlexaAuthError } from '../src/gateway.js';
import type { WakePlan, WakeRun } from '../src/scheduler.js';
import { applyWakeActions, runWake, type WakeStore } from '../src/wake.js';
import { FakeGateway } from './fake-gateway.js';

const plan = (over: Partial<WakePlan> = {}): WakePlan => ({
  id: 'p1', label: 'Aula', days: [1], time: '07:00', echoDeviceId: 'ECHO', spotifyQuery: 'lofi',
  musicFirst: true, briefingDelayMin: 3, volume: 30, fallbackAlarm: true, enabled: true, ...over,
});

class MemoryWakeStore implements WakeStore {
  log: string[] = [];
  claimed = new Set<string>();
  async armRun(planId: string, runDate: string, plannedFor: Date, handle: string) { this.log.push(`arm ${planId} ${runDate} ${plannedFor.toISOString()} ${handle}`); }
  async setRunStatus(runId: string, status: string) { this.log.push(`status ${runId} ${status}`); }
  async claimRun(planId: string, runDate: string) {
    const key = `${planId}:${runDate}`;
    if (this.claimed.has(key)) return false;
    this.claimed.add(key);
    return true;
  }
  async finishRun(planId: string, runDate: string, status: string, note: string) { this.log.push(`finish ${planId} ${runDate} ${status} ${note}`); }
}

const noSleep = async () => {};

describe('runWake', () => {
  it('música antes: volume → Spotify → espera → fala', async () => {
    const gw = new FakeGateway();
    const waits: number[] = [];
    const r = await runWake(plan(), 'Bom dia!', gw, async (ms) => { waits.push(ms); });
    expect(r).toEqual({ ok: true, notes: [] });
    expect(gw.calls).toEqual(['setVolume(ECHO,30)', 'playSpotify(ECHO,lofi)', 'speak(ECHO,Bom dia!)']);
    expect(waits).toEqual([180_000]);
  });

  it('Spotify falhando: ainda fala o resumo e conta como sucesso', async () => {
    const gw = new FakeGateway();
    gw.failOn.add('playSpotify');
    const r = await runWake(plan(), 'Bom dia!', gw, noSleep);
    expect(r.ok).toBe(true);
    expect(r.notes).toEqual(['spotify: playSpotify falhou']);
    expect(gw.calls).toContain('speak(ECHO,Bom dia!)');
  });

  it('nada tocou: ok=false', async () => {
    const gw = new FakeGateway();
    gw.failOn.add('playSpotify');
    gw.failOn.add('speak');
    expect((await runWake(plan(), 'Bom dia!', gw, noSleep)).ok).toBe(false);
  });

  it('resumo primeiro quando musicFirst=false', async () => {
    const gw = new FakeGateway();
    await runWake(plan({ musicFirst: false }), 'Oi.', gw, noSleep);
    expect(gw.calls).toEqual(['setVolume(ECHO,30)', 'speak(ECHO,Oi.)', 'playSpotify(ECHO,lofi)']);
  });

  it('erro de login é propagado', async () => {
    const gw = new FakeGateway();
    gw.setVolume = async () => { throw new AlexaAuthError('cookie expirado'); };
    await expect(runWake(plan(), 'x', gw, noSleep)).rejects.toBeInstanceOf(AlexaAuthError);
  });
});

describe('applyWakeActions', () => {
  const deps = (gw: FakeGateway, store: MemoryWakeStore) =>
    ({ gateway: gw, store, briefing: async () => 'Bom dia!', sleep: noSleep, log: () => {} });

  it('arma: cria alarme reserva e grava o run', async () => {
    const gw = new FakeGateway();
    const store = new MemoryWakeStore();
    await applyWakeActions([{
      type: 'arm', plan: plan(), runDate: '2026-09-28',
      plannedFor: new Date('2026-09-28T10:00:00Z'), fallbackAt: new Date('2026-09-28T10:10:00Z'),
    }], deps(gw, store), new Set());
    expect(gw.calls).toEqual(['createAlarm(ECHO,2026-09-28T10:10:00.000Z,Aula (reserva))']);
    expect(store.log).toEqual(['arm p1 2026-09-28 2026-09-28T10:00:00.000Z alarme-1']);
  });

  it('dispara uma vez e apaga o alarme reserva quando deu certo', async () => {
    const gw = new FakeGateway();
    const store = new MemoryWakeStore();
    const armed: WakeRun = { id: 'r1', planId: 'p1', runDate: '2026-09-28', plannedFor: new Date('2026-09-28T10:00:00Z'), status: 'armed', fallbackHandle: 'reserva-1' };
    const fire = { type: 'fire' as const, plan: plan(), runDate: '2026-09-28', plannedFor: armed.plannedFor, run: armed };
    const inFlight = new Set<string>();
    const first = await applyWakeActions([fire], deps(gw, store), inFlight);
    const second = await applyWakeActions([fire], deps(gw, store), inFlight);
    await Promise.all([...first, ...second]);
    expect(gw.calls.filter((c) => c.startsWith('playSpotify'))).toHaveLength(1);
    expect(gw.calls).toContain('deleteAlarm(reserva-1)');
    expect(store.log).toEqual(['finish p1 2026-09-28 done ']);
  });

  it('se nada tocou, mantém o alarme reserva e marca failed', async () => {
    const gw = new FakeGateway();
    gw.failOn.add('playSpotify');
    gw.failOn.add('speak');
    const store = new MemoryWakeStore();
    const armed: WakeRun = { id: 'r1', planId: 'p1', runDate: '2026-09-28', plannedFor: new Date(), status: 'armed', fallbackHandle: 'reserva-1' };
    const pending = await applyWakeActions([{ type: 'fire', plan: plan(), runDate: '2026-09-28', plannedFor: armed.plannedFor, run: armed }], deps(gw, store), new Set());
    await Promise.all(pending);
    expect(gw.calls).not.toContain('deleteAlarm(reserva-1)');
    expect(store.log[0]).toMatch(/^finish p1 2026-09-28 failed spotify: playSpotify falhou; fala: speak falhou/);
  });

  it('cancelar apaga o alarme e marca cancelled; miss só marca', async () => {
    const gw = new FakeGateway();
    const store = new MemoryWakeStore();
    const armed: WakeRun = { id: 'r1', planId: null, runDate: '2026-09-28', plannedFor: new Date(), status: 'armed', fallbackHandle: 'reserva-1' };
    await applyWakeActions([{ type: 'cancel', run: armed }, { type: 'miss', run: { ...armed, id: 'r2' } }], deps(gw, store), new Set());
    expect(gw.calls).toEqual(['deleteAlarm(reserva-1)']);
    expect(store.log).toEqual(['status r1 cancelled', 'status r2 missed']);
  });
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd bridge && npx vitest run test/commands.test.ts test/wake.test.ts`
Expected: FAIL (módulos não existem).

- [ ] **Step 3: Implementar**

Create `bridge/src/gateway.ts`:
```ts
export type DeviceAction = 'turnOn' | 'turnOff' | 'setBrightness';

export interface EchoDevice { id: string; name: string; online: boolean }
export interface SmartDevice { id: string; name: string; operations: string[] }
export interface Routine { id: string; name: string }

/** Login da Alexa inválido/expirado: a ponte precisa de `npm run login`. */
export class AlexaAuthError extends Error {}

export interface AlexaGateway {
  listEchos(): Promise<EchoDevice[]>;
  listSmartDevices(): Promise<SmartDevice[]>;
  listRoutines(): Promise<Routine[]>;
  runRoutine(routineId: string, echoDeviceId: string): Promise<void>;
  deviceAction(entityId: string, action: DeviceAction, brightness?: number): Promise<void>;
  speak(echoDeviceId: string, text: string): Promise<void>;
  setVolume(echoDeviceId: string, volume: number): Promise<void>;
  playSpotify(echoDeviceId: string, query: string): Promise<void>;
  /** Devolve um identificador opaco para apagar o alarme depois. */
  createAlarm(echoDeviceId: string, at: Date, label: string): Promise<string>;
  deleteAlarm(handle: string): Promise<void>;
}
```

Create `bridge/src/commands.ts`:
```ts
import { chunkSpeech } from './briefing.js';
import type { AlexaGateway, DeviceAction } from './gateway.js';

export type CommandKind = 'device' | 'routine' | 'speak' | 'music' | 'sync' | 'wake_test';

export interface Command {
  id: string;
  kind: CommandKind;
  payload: Record<string, unknown>;
  createdAt: Date;
}

export class CommandError extends Error {}

export const COMMAND_MAX_AGE_MS = 120_000;

export const isExpired = (cmd: Command, now: Date, maxAgeMs = COMMAND_MAX_AGE_MS) =>
  now.getTime() - cmd.createdAt.getTime() > maxAgeMs;

export interface CommandDeps {
  gateway: AlexaGateway;
  sync: () => Promise<void>;
  wakeTest: (planId: string) => Promise<string>;
}

const DEVICE_ACTIONS: DeviceAction[] = ['turnOn', 'turnOff', 'setBrightness'];

function str(payload: Record<string, unknown>, key: string): string {
  const v = payload[key];
  if (typeof v !== 'string' || !v.trim()) throw new CommandError(`campo "${key}" ausente`);
  return v;
}

export async function executeCommand(cmd: Command, deps: CommandDeps): Promise<string> {
  const p = cmd.payload;
  switch (cmd.kind) {
    case 'device': {
      const action = str(p, 'action');
      if (!DEVICE_ACTIONS.includes(action as DeviceAction)) throw new CommandError(`ação desconhecida: ${action}`);
      let brightness: number | undefined;
      if (action === 'setBrightness') {
        brightness = Number(p.brightness);
        if (!Number.isInteger(brightness) || brightness < 0 || brightness > 100) {
          throw new CommandError('brilho deve ser de 0 a 100');
        }
      }
      await deps.gateway.deviceAction(str(p, 'entityId'), action as DeviceAction, brightness);
      return 'ok';
    }
    case 'routine':
      await deps.gateway.runRoutine(str(p, 'routineId'), str(p, 'echoDeviceId'));
      return 'ok';
    case 'speak': {
      const echo = str(p, 'echoDeviceId');
      for (const chunk of chunkSpeech(str(p, 'text'))) await deps.gateway.speak(echo, chunk);
      return 'ok';
    }
    case 'music':
      await deps.gateway.playSpotify(str(p, 'echoDeviceId'), str(p, 'query'));
      return 'ok';
    case 'sync':
      await deps.sync();
      return 'ok';
    case 'wake_test':
      return deps.wakeTest(str(p, 'planId'));
    default:
      throw new CommandError(`tipo desconhecido: ${String(cmd.kind)}`);
  }
}
```

Create `bridge/src/wake.ts`:
```ts
import { chunkSpeech } from './briefing.js';
import { AlexaAuthError, type AlexaGateway } from './gateway.js';
import type { RunStatus, WakeAction, WakePlan } from './scheduler.js';

export interface WakeResult { ok: boolean; notes: string[] }

export async function runWake(
  plan: WakePlan,
  briefing: string,
  gateway: AlexaGateway,
  sleep: (ms: number) => Promise<void>,
): Promise<WakeResult> {
  const notes: string[] = [];
  let audio = false;
  const attempt = async (label: string, fn: () => Promise<void>): Promise<boolean> => {
    try {
      await fn();
      return true;
    } catch (e) {
      if (e instanceof AlexaAuthError) throw e;
      notes.push(`${label}: ${(e as Error).message}`);
      return false;
    }
  };
  const music = async () => {
    const query = plan.spotifyQuery?.trim();
    if (!query) return false;
    const played = await attempt('spotify', () => gateway.playSpotify(plan.echoDeviceId, query));
    audio ||= played;
    return played;
  };
  const speak = async () => {
    for (const chunk of chunkSpeech(briefing)) {
      if (!(await attempt('fala', () => gateway.speak(plan.echoDeviceId, chunk)))) return;
      audio = true;
    }
  };

  await attempt('volume', () => gateway.setVolume(plan.echoDeviceId, plan.volume));
  if (plan.musicFirst) {
    if (await music()) await sleep(plan.briefingDelayMin * 60_000);
    await speak();
  } else {
    await speak();
    await music();
  }
  return { ok: audio, notes };
}

export interface WakeStore {
  armRun(planId: string, runDate: string, plannedFor: Date, fallbackHandle: string): Promise<void>;
  setRunStatus(runId: string, status: RunStatus, note?: string | null): Promise<void>;
  claimRun(planId: string, runDate: string, plannedFor: Date): Promise<boolean>;
  finishRun(planId: string, runDate: string, status: 'done' | 'failed', note: string): Promise<void>;
}

export interface WakeDeps {
  gateway: AlexaGateway;
  store: WakeStore;
  briefing: () => Promise<string>;
  sleep: (ms: number) => Promise<void>;
  log: (msg: string) => void;
}

type FireAction = Extract<WakeAction, { type: 'fire' }>;

async function fireWake(a: FireAction, deps: WakeDeps): Promise<void> {
  try {
    const result = await runWake(a.plan, await deps.briefing(), deps.gateway, deps.sleep);
    const handle = a.run?.fallbackHandle;
    if (result.ok && handle) {
      await deps.gateway.deleteAlarm(handle).catch((e: Error) => deps.log(`não apagou o alarme reserva: ${e.message}`));
    }
    await deps.store.finishRun(a.plan.id, a.runDate, result.ok ? 'done' : 'failed', result.notes.join('; '));
  } catch (e) {
    deps.log(`despertar ${a.plan.label} falhou: ${(e as Error).message}`);
    await deps.store.finishRun(a.plan.id, a.runDate, 'failed', (e as Error).message).catch(() => {});
    if (e instanceof AlexaAuthError) throw e;
  }
}

export async function applyWakeActions(
  actions: WakeAction[],
  deps: WakeDeps,
  inFlight: Set<string>,
): Promise<Promise<void>[]> {
  const running: Promise<void>[] = [];
  for (const a of actions) {
    try {
      switch (a.type) {
        case 'arm': {
          const handle = await deps.gateway.createAlarm(a.plan.echoDeviceId, a.fallbackAt, `${a.plan.label} (reserva)`);
          await deps.store.armRun(a.plan.id, a.runDate, a.plannedFor, handle);
          break;
        }
        case 'rearm': {
          if (a.run.fallbackHandle) await deps.gateway.deleteAlarm(a.run.fallbackHandle).catch(() => {});
          const handle = await deps.gateway.createAlarm(a.plan.echoDeviceId, a.fallbackAt, `${a.plan.label} (reserva)`);
          await deps.store.armRun(a.plan.id, a.run.runDate, a.plannedFor, handle);
          break;
        }
        case 'cancel':
          if (a.run.fallbackHandle) {
            await deps.gateway.deleteAlarm(a.run.fallbackHandle).catch((e: Error) => deps.log(`não apagou alarme: ${e.message}`));
          }
          await deps.store.setRunStatus(a.run.id, 'cancelled');
          break;
        case 'miss':
          await deps.store.setRunStatus(a.run.id, 'missed', 'a ponte não disparou no horário; o alarme reserva tocou');
          break;
        case 'fire': {
          const key = `${a.plan.id}:${a.runDate}`;
          if (inFlight.has(key)) break;
          if (!(await deps.store.claimRun(a.plan.id, a.runDate, a.plannedFor))) break;
          inFlight.add(key);
          running.push(fireWake(a, deps).finally(() => inFlight.delete(key)));
          break;
        }
      }
    } catch (e) {
      if (e instanceof AlexaAuthError) throw e;
      deps.log(`falha em ${a.type}: ${(e as Error).message}`);
    }
  }
  return running;
}
```

- [ ] **Step 4: Rodar e ver passar**

Run: `npx vitest run && npx tsc -p tsconfig.json --noEmit`
Expected: todos passam; `tsc` sem erros.

- [ ] **Step 5: Commit**

```bash
cd /home/only/organizacional
git add bridge/src/gateway.ts bridge/src/commands.ts bridge/src/wake.ts bridge/test
git commit -m "feat(ponte): comandos e execução do despertar com alarme reserva"
```

---

### Task 5: Skill oficial "Organizacional"

**Files:**
- Create: `bridge/src/skill.ts`, `bridge/skill/interaction-model.pt-BR.json`
- Test: `bridge/test/skill.test.ts`

**Interfaces:**
- Consumes: `buildBriefing`, `headlinesText`, `escapeSsml`, `BriefingInput` (Task 2).
- Produces: `interface SkillDeps { allowedUserId: string | null; briefingInput: () => Promise<BriefingInput>; log: (m: string) => void }`; `buildSkill(deps): Skill` (ask-sdk-core). Intents: `ResumoDoDiaIntent`, `NoticiasIntent`, mais `LaunchRequest` e os intents `AMAZON.*`.

- [ ] **Step 1: Escrever os testes**

Create `bridge/test/skill.test.ts`:
```ts
import { describe, expect, it } from 'vitest';
import type { BriefingInput } from '../src/briefing.js';
import { buildSkill } from '../src/skill.js';

const USER = 'amzn1.ask.account.EU';
const input: BriefingInput = {
  now: new Date('2026-09-28T10:00:00Z'),
  timeZone: 'America/Sao_Paulo',
  events: [{ title: 'P&D <Lab>', startsAt: new Date('2026-09-28T11:00:00Z'), endsAt: new Date('2026-09-28T12:00:00Z'), allDay: false, location: null }],
  overdue: [],
  dueToday: [],
  news: [{ source: 'G1', title: 'Chuva forte' }],
};

function envelope(request: Record<string, unknown>, userId = USER) {
  return {
    version: '1.0',
    session: { new: true, sessionId: 's', application: { applicationId: 'app' }, user: { userId } },
    context: { System: { application: { applicationId: 'app' }, user: { userId }, apiEndpoint: 'https://api.amazonalexa.com' } },
    request: { requestId: 'r', timestamp: new Date().toISOString(), locale: 'pt-BR', ...request },
  };
}

const intent = (name: string) => ({ type: 'IntentRequest', intent: { name, confirmationStatus: 'NONE' } });

async function ssml(skill: ReturnType<typeof buildSkill>, request: Record<string, unknown>, userId = USER) {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const res = await skill.invoke(envelope(request, userId) as any);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return (res.response.outputSpeech as any)?.ssml as string;
}

describe('skill', () => {
  const logs: string[] = [];
  const skill = buildSkill({ allowedUserId: USER, briefingInput: async () => input, log: (m) => logs.push(m) });

  it('abrir a skill fala o resumo com SSML escapado', async () => {
    const out = await ssml(skill, { type: 'LaunchRequest' });
    expect(out).toContain('Bom dia! Hoje é segunda-feira, 28 de setembro.');
    expect(out).toContain('P&amp;D &lt;Lab&gt;');
    expect(out).not.toContain('<Lab>');
  });

  it('ResumoDoDiaIntent e NoticiasIntent', async () => {
    expect(await ssml(skill, intent('ResumoDoDiaIntent'))).toContain('Você tem 1 compromisso');
    expect(await ssml(skill, intent('NoticiasIntent'))).toContain('Manchetes: G1: Chuva forte.');
  });

  it('outra conta Amazon recebe recusa', async () => {
    expect(await ssml(skill, { type: 'LaunchRequest' }, 'amzn1.ask.account.OUTRO')).toContain('Esta skill é privada.');
  });

  it('sem ALEXA_ALLOWED_USER_ID configurado, loga o id da conta', async () => {
    const seen: string[] = [];
    const open = buildSkill({ allowedUserId: null, briefingInput: async () => input, log: (m) => seen.push(m) });
    expect(await ssml(open, { type: 'LaunchRequest' })).toContain('ainda não configurada');
    expect(seen.join('\n')).toContain(USER);
  });

  it('erro ao ler a agenda vira mensagem amigável', async () => {
    const broken = buildSkill({ allowedUserId: USER, briefingInput: async () => { throw new Error('db fora'); }, log: () => {} });
    expect(await ssml(broken, { type: 'LaunchRequest' })).toContain('Não consegui acessar sua agenda agora.');
  });

  it('parar se despede', async () => {
    expect(await ssml(skill, intent('AMAZON.StopIntent'))).toContain('Até mais!');
  });
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd bridge && npx vitest run test/skill.test.ts`
Expected: FAIL (`skill.ts` não existe).

- [ ] **Step 3: Implementar a skill e o modelo de interação**

Create `bridge/src/skill.ts`:
```ts
import askCore from 'ask-sdk-core';
import type { ErrorHandler, HandlerInput, RequestHandler, Skill } from 'ask-sdk-core';
import { buildBriefing, escapeSsml, headlinesText, type BriefingInput } from './briefing.js';

const { SkillBuilders, getRequestType, getIntentName, getUserId } = askCore;

export interface SkillDeps {
  allowedUserId: string | null;
  briefingInput: () => Promise<BriefingInput>;
  log: (m: string) => void;
}

export function buildSkill(deps: SkillDeps): Skill {
  const say = (h: HandlerInput, text: string) =>
    h.responseBuilder.speak(escapeSsml(text)).withShouldEndSession(true).getResponse();
  const isType = (h: HandlerInput, type: string) => getRequestType(h.requestEnvelope) === type;
  const isIntent = (h: HandlerInput, ...names: string[]) =>
    isType(h, 'IntentRequest') && names.includes(getIntentName(h.requestEnvelope));

  const guard: RequestHandler = {
    canHandle: (h) => deps.allowedUserId === null || getUserId(h.requestEnvelope) !== deps.allowedUserId,
    handle: (h) => {
      deps.log(`skill chamada pela conta ${getUserId(h.requestEnvelope)}`);
      return say(h, deps.allowedUserId === null
        ? 'Skill ainda não configurada. Veja no log da ponte o identificador desta conta.'
        : 'Esta skill é privada.');
    },
  };
  const briefing: RequestHandler = {
    canHandle: (h) => isType(h, 'LaunchRequest') || isIntent(h, 'ResumoDoDiaIntent'),
    handle: async (h) => say(h, buildBriefing(await deps.briefingInput())),
  };
  const news: RequestHandler = {
    canHandle: (h) => isIntent(h, 'NoticiasIntent'),
    handle: async (h) => say(h, headlinesText((await deps.briefingInput()).news)),
  };
  const help: RequestHandler = {
    canHandle: (h) => isIntent(h, 'AMAZON.HelpIntent', 'AMAZON.FallbackIntent'),
    handle: (h) =>
      h.responseBuilder
        .speak('Você pode dizer: qual é o meu dia. Ou: quais são as notícias.')
        .reprompt('O que você quer saber?')
        .getResponse(),
  };
  const stop: RequestHandler = {
    canHandle: (h) => isIntent(h, 'AMAZON.StopIntent', 'AMAZON.CancelIntent', 'AMAZON.NavigateHomeIntent'),
    handle: (h) => say(h, 'Até mais!'),
  };
  const ended: RequestHandler = {
    canHandle: (h) => isType(h, 'SessionEndedRequest'),
    handle: (h) => h.responseBuilder.getResponse(),
  };
  const errors: ErrorHandler = {
    canHandle: () => true,
    handle: (h, error) => {
      deps.log(`erro na skill: ${error.message}`);
      return say(h, 'Não consegui acessar sua agenda agora. Tente de novo em instantes.');
    },
  };

  return SkillBuilders.custom()
    .addRequestHandlers(guard, briefing, news, help, stop, ended)
    .addErrorHandlers(errors)
    .create();
}
```

Create `bridge/skill/interaction-model.pt-BR.json`:
```json
{
  "interactionModel": {
    "languageModel": {
      "invocationName": "organizacional",
      "intents": [
        {
          "name": "ResumoDoDiaIntent",
          "slots": [],
          "samples": ["qual é o meu dia", "o que eu tenho hoje", "meu resumo", "resumo do dia", "como está minha agenda", "minha agenda de hoje"]
        },
        {
          "name": "NoticiasIntent",
          "slots": [],
          "samples": ["quais são as notícias", "notícias", "manchetes", "me conta as notícias", "o que está acontecendo"]
        },
        { "name": "AMAZON.HelpIntent", "samples": [] },
        { "name": "AMAZON.StopIntent", "samples": [] },
        { "name": "AMAZON.CancelIntent", "samples": [] },
        { "name": "AMAZON.NavigateHomeIntent", "samples": [] },
        { "name": "AMAZON.FallbackIntent", "samples": [] }
      ],
      "types": []
    }
  }
}
```

- [ ] **Step 4: Rodar e ver passar**

Run: `npx vitest run && npx tsc -p tsconfig.json --noEmit`
Expected: todos passam; `tsc` sem erros. Se o `tsc` reclamar do default import de `ask-sdk-core`, troque por `import * as askCore from 'ask-sdk-core'` (e mantenha a desestruturação).

- [ ] **Step 5: Commit**

```bash
cd /home/only/organizacional
git add bridge/src/skill.ts bridge/skill bridge/test/skill.test.ts
git commit -m "feat(ponte): skill oficial com resumo do dia e notícias"
```

---

### Task 6: Store Supabase, gateway real e processo principal

**Files:**
- Create: `bridge/src/supabase-store.ts`, `bridge/src/alexa-remote-gateway.ts`, `bridge/src/main.ts`, `bridge/src/scripts/login.ts`, `bridge/src/scripts/smoke.ts`
- Test: `bridge/test/mappers.test.ts`, `bridge/test/supabase-store.test.ts` (integração; pulado sem variáveis de ambiente)

**Interfaces:**
- Consumes: Tasks 1–5.
- Produces:
  - `class SupabaseStore implements WakeStore` (`constructor(db: SupabaseClient, userId: string, log: (m: string) => void)`) com `briefingInput(now, timeZone): Promise<BriefingInput>`, `listWakePlans()`, `listWakeRuns(sinceDate)`, `pendingCommands()`, `claimCommand(id)`, `finishCommand(id, status: 'done' | 'failed' | 'expired', result)`, `onNewCommand(cb): () => void`, `saveDevices(echos, smart)`, `saveRoutines(routines)`, `setStatus(state, message)`, `heartbeat()`
  - `class AlexaRemoteGateway implements AlexaGateway` com `static connect(opts: { cookieFile; amazonPage; alexaServiceHost; language })`; `mapSmartEntities(raw: unknown): SmartDevice[]`; `mapRoutines(raw: unknown): Routine[]`
  - Processo `node dist/main.js`: HTTP `POST /alexa`, `GET /health`; loops de heartbeat (60 s), comandos (realtime + varredura a cada 15 s), sincronização (10 min) e despertador (30 s)

- [ ] **Step 1: Escrever os testes**

Create `bridge/test/mappers.test.ts`:
```ts
import { describe, expect, it } from 'vitest';
import { mapRoutines, mapSmartEntities } from '../src/alexa-remote-gateway.js';

describe('mapSmartEntities', () => {
  it('mantém só dispositivos controláveis e as operações conhecidas', () => {
    const raw = [
      { id: 'e1', displayName: 'Luz do quarto', supportedOperations: ['turnOn', 'turnOff', 'setBrightness', 'setColor'] },
      { id: 'e2', displayName: 'Sensor da porta', supportedOperations: [] },
      { id: 'e3', displayName: 'Tomada', supportedOperations: ['turnOff', 'turnOn'] },
      { displayName: 'sem id' },
    ];
    expect(mapSmartEntities(raw)).toEqual([
      { id: 'e1', name: 'Luz do quarto', operations: ['turnOn', 'turnOff', 'setBrightness'] },
      { id: 'e3', name: 'Tomada', operations: ['turnOn', 'turnOff'] },
    ]);
  });

  it('resposta inesperada vira lista vazia', () => {
    expect(mapSmartEntities({ erro: true })).toEqual([]);
  });
});

describe('mapRoutines', () => {
  it('usa o nome ou a frase de ativação', () => {
    const raw = [
      { automationId: 'a1', name: 'Boa noite' },
      { automationId: 'a2', name: null, triggers: [{ payload: { utterance: 'hora de estudar' } }] },
      { automationId: 'a3' },
      { name: 'sem id' },
    ];
    expect(mapRoutines(raw)).toEqual([
      { id: 'a1', name: 'Boa noite' },
      { id: 'a2', name: 'hora de estudar' },
      { id: 'a3', name: 'Rotina sem nome' },
    ]);
  });
});
```

Create `bridge/test/supabase-store.test.ts`:
```ts
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { beforeAll, describe, expect, it } from 'vitest';
import { SupabaseStore } from '../src/supabase-store.js';

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;

describe.skipIf(!url || !key)('SupabaseStore (integração)', () => {
  let db: SupabaseClient;
  let store: SupabaseStore;
  let userId: string;

  beforeAll(async () => {
    db = createClient(url!, key!, { auth: { persistSession: false } });
    const { data, error } = await db.auth.admin.createUser({
      email: `ponte-${Date.now()}@local.test`, password: 'senha-de-teste-123', email_confirm: true,
    });
    if (error) throw error;
    userId = data.user.id;
    store = new SupabaseStore(db, userId, () => {});
  });

  const newPlan = async () => {
    const { data, error } = await db.from('wake_plans')
      .insert({ user_id: userId, label: 'Teste', days: [1, 2, 3, 4, 5, 6, 7], time: '07:00', echo_device_id: 'ECHO' })
      .select().single();
    if (error) throw error;
    return data.id as string;
  };

  it('reivindica o despertar uma única vez', async () => {
    const planId = await newPlan();
    const at = new Date('2026-09-28T10:00:00Z');
    expect(await store.claimRun(planId, '2026-09-28', at)).toBe(true);
    expect(await store.claimRun(planId, '2026-09-28', at)).toBe(false);
  });

  it('run armado pode ser reivindicado; concluído não', async () => {
    const planId = await newPlan();
    const at = new Date('2026-09-29T10:00:00Z');
    await store.armRun(planId, '2026-09-29', at, 'reserva');
    expect((await store.listWakeRuns('2026-09-29')).find((r) => r.planId === planId)?.fallbackHandle).toBe('reserva');
    expect(await store.claimRun(planId, '2026-09-29', at)).toBe(true);
    await store.finishRun(planId, '2026-09-29', 'done', '');
    expect(await store.claimRun(planId, '2026-09-29', at)).toBe(false);
  });

  it('comando é reivindicado uma vez e sai da fila', async () => {
    const { data } = await db.from('alexa_commands')
      .insert({ user_id: userId, kind: 'speak', payload: { text: 'oi' } }).select().single();
    expect((await store.pendingCommands()).map((c) => c.id)).toContain(data!.id);
    expect(await store.claimCommand(data!.id)).toBe(true);
    expect(await store.claimCommand(data!.id)).toBe(false);
    await store.finishCommand(data!.id, 'done', 'ok');
    expect((await store.pendingCommands()).map((c) => c.id)).not.toContain(data!.id);
  });

  it('briefingInput respeita o dia local de São Paulo', async () => {
    await db.from('events').insert([
      { user_id: userId, title: 'Manhã', starts_at: '2026-09-28T11:00:00Z', ends_at: '2026-09-28T12:00:00Z' },
      { user_id: userId, title: 'Noite', starts_at: '2026-09-29T02:30:00Z', ends_at: '2026-09-29T02:50:00Z' },
      { user_id: userId, title: 'Amanhã', starts_at: '2026-09-29T03:30:00Z', ends_at: '2026-09-29T04:00:00Z' },
    ]);
    await db.from('tasks').insert([
      { user_id: userId, title: 'Atrasada', due_at: '2026-09-27T20:00:00Z' },
      { user_id: userId, title: 'Hoje', due_at: '2026-09-28T20:00:00Z' },
      { user_id: userId, title: 'Feita', due_at: '2026-09-28T20:00:00Z', status: 'done' },
    ]);
    const input = await store.briefingInput(new Date('2026-09-28T13:00:00Z'), 'America/Sao_Paulo');
    expect(input.events.map((e) => e.title)).toEqual(['Manhã', 'Noite']);
    expect(input.overdue.map((t) => t.title)).toEqual(['Atrasada']);
    expect(input.dueToday.map((t) => t.title)).toEqual(['Hoje']);
  });

  it('saveDevices remove dispositivos que sumiram', async () => {
    await store.saveDevices([{ id: 'E1', name: 'Echo', online: true }], [{ id: 'L1', name: 'Luz', operations: ['turnOn'] }]);
    await store.saveDevices([{ id: 'E1', name: 'Echo', online: false }], []);
    const { data } = await db.from('alexa_devices').select('id, online').eq('user_id', userId);
    expect(data).toEqual([{ id: 'E1', online: false }]);
  });
});
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd bridge && npx vitest run test/mappers.test.ts`
Expected: FAIL (`alexa-remote-gateway.ts` não existe).

- [ ] **Step 3: Implementar o store**

Create `bridge/src/supabase-store.ts`:
```ts
import type { SupabaseClient } from '@supabase/supabase-js';
import { splitTasks, type BriefingInput } from './briefing.js';
import type { Command, CommandKind } from './commands.js';
import type { EchoDevice, Routine, SmartDevice } from './gateway.js';
import type { RunStatus, WakePlan, WakeRun } from './scheduler.js';
import { zonedDayRange } from './time.js';
import type { WakeStore } from './wake.js';

export type BridgeState = 'ok' | 'auth_required' | 'error';

type Row = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any

const toCommand = (r: Row): Command => ({
  id: r.id,
  kind: r.kind as CommandKind,
  payload: (r.payload ?? {}) as Record<string, unknown>,
  createdAt: new Date(r.created_at),
});

const toPlan = (r: Row): WakePlan => ({
  id: r.id,
  label: r.label,
  days: r.days,
  time: r.time,
  echoDeviceId: r.echo_device_id,
  spotifyQuery: r.spotify_query,
  musicFirst: r.music_first,
  briefingDelayMin: r.briefing_delay_min,
  volume: r.volume,
  fallbackAlarm: r.fallback_alarm,
  enabled: r.enabled,
});

const toRun = (r: Row): WakeRun => ({
  id: r.id,
  planId: r.plan_id,
  runDate: r.run_date,
  plannedFor: new Date(r.planned_for),
  status: r.status as RunStatus,
  fallbackHandle: r.fallback_handle,
});

export class SupabaseStore implements WakeStore {
  constructor(
    private readonly db: SupabaseClient,
    private readonly userId: string,
    private readonly log: (m: string) => void,
  ) {}

  private check<T>(res: { data: T; error: { message: string } | null }): T {
    if (res.error) throw new Error(res.error.message);
    return res.data;
  }

  async briefingInput(now: Date, timeZone: string): Promise<BriefingInput> {
    const { start, end } = zonedDayRange(now, timeZone);
    const events = this.check(await this.db.from('events')
      .select('title, starts_at, ends_at, all_day, location')
      .eq('user_id', this.userId)
      .lt('starts_at', end.toISOString())
      .gt('ends_at', start.toISOString())
      .order('starts_at')) as Row[];
    const tasks = this.check(await this.db.from('tasks')
      .select('title, due_at')
      .eq('user_id', this.userId)
      .neq('status', 'done')
      .not('due_at', 'is', null)
      .lt('due_at', end.toISOString())
      .order('due_at')) as Row[];
    const { overdue, dueToday } = splitTasks(tasks.map((t) => ({ title: t.title, dueAt: new Date(t.due_at) })), start);

    let news: BriefingInput['news'] = [];
    try {
      const prefs = this.check(await this.db.from('news_prefs')
        .select('briefing_count').eq('user_id', this.userId).maybeSingle()) as Row | null;
      const count = (prefs?.briefing_count as number | undefined) ?? 3;
      if (count > 0) {
        const rows = this.check(await this.db.rpc('news_feed', { p_user: this.userId, p_limit: count })) as Row[];
        news = rows.map((r) => ({ title: r.title, source: r.source_name }));
      }
    } catch (e) {
      this.log(`notícias indisponíveis: ${(e as Error).message}`);
    }

    return {
      now,
      timeZone,
      events: events.map((e) => ({
        title: e.title, startsAt: new Date(e.starts_at), endsAt: new Date(e.ends_at),
        allDay: e.all_day, location: e.location,
      })),
      overdue,
      dueToday,
      news,
    };
  }

  async listWakePlans(): Promise<WakePlan[]> {
    return (this.check(await this.db.from('wake_plans').select('*').eq('user_id', this.userId)) as Row[]).map(toPlan);
  }

  async listWakeRuns(sinceDate: string): Promise<WakeRun[]> {
    return (this.check(await this.db.from('wake_runs').select('*')
      .eq('user_id', this.userId).gte('run_date', sinceDate)) as Row[]).map(toRun);
  }

  async armRun(planId: string, runDate: string, plannedFor: Date, fallbackHandle: string): Promise<void> {
    this.check(await this.db.from('wake_runs').upsert({
      user_id: this.userId, plan_id: planId, run_date: runDate, planned_for: plannedFor.toISOString(),
      status: 'armed', fallback_handle: fallbackHandle, note: null,
    }, { onConflict: 'plan_id,run_date' }));
  }

  async setRunStatus(runId: string, status: RunStatus, note: string | null = null): Promise<void> {
    this.check(await this.db.from('wake_runs').update({ status, note }).eq('id', runId));
  }

  async claimRun(planId: string, runDate: string, plannedFor: Date): Promise<boolean> {
    return Boolean(this.check(await this.db.rpc('claim_wake_run', {
      p_user: this.userId, p_plan: planId, p_date: runDate, p_planned: plannedFor.toISOString(),
    })));
  }

  async finishRun(planId: string, runDate: string, status: 'done' | 'failed', note: string): Promise<void> {
    this.check(await this.db.from('wake_runs').update({ status, note })
      .eq('plan_id', planId).eq('run_date', runDate));
  }

  async pendingCommands(): Promise<Command[]> {
    return (this.check(await this.db.from('alexa_commands').select('id, kind, payload, created_at')
      .eq('user_id', this.userId).eq('status', 'pending').order('created_at')) as Row[]).map(toCommand);
  }

  async claimCommand(id: string): Promise<boolean> {
    return Boolean(this.check(await this.db.rpc('claim_command', { p_id: id })));
  }

  async finishCommand(id: string, status: 'done' | 'failed' | 'expired', result: string): Promise<void> {
    this.check(await this.db.from('alexa_commands')
      .update({ status, result, finished_at: new Date().toISOString() }).eq('id', id));
  }

  onNewCommand(cb: (cmd: Command) => void): () => void {
    const channel = this.db.channel('alexa-commands')
      .on('postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'alexa_commands', filter: `user_id=eq.${this.userId}` },
        (payload) => cb(toCommand(payload.new as Row)))
      .subscribe();
    return () => { void this.db.removeChannel(channel); };
  }

  private async deleteStale(table: string, keep: string[]): Promise<void> {
    let query = this.db.from(table).delete().eq('user_id', this.userId);
    if (keep.length) query = query.not('id', 'in', `(${keep.map((id) => `"${id.replace(/"/g, '\\"')}"`).join(',')})`);
    this.check(await query);
  }

  async saveDevices(echos: EchoDevice[], smart: SmartDevice[]): Promise<void> {
    const now = new Date().toISOString();
    const rows = [
      ...echos.map((e) => ({ user_id: this.userId, id: e.id, name: e.name, kind: 'echo', operations: [], online: e.online, updated_at: now })),
      ...smart.map((s) => ({ user_id: this.userId, id: s.id, name: s.name, kind: 'smart', operations: s.operations, online: true, updated_at: now })),
    ];
    if (rows.length) this.check(await this.db.from('alexa_devices').upsert(rows, { onConflict: 'user_id,id' }));
    await this.deleteStale('alexa_devices', rows.map((r) => r.id));
  }

  async saveRoutines(routines: Routine[]): Promise<void> {
    const now = new Date().toISOString();
    const rows = routines.map((r) => ({ user_id: this.userId, id: r.id, name: r.name, updated_at: now }));
    if (rows.length) this.check(await this.db.from('alexa_routines').upsert(rows, { onConflict: 'user_id,id' }));
    await this.deleteStale('alexa_routines', rows.map((r) => r.id));
  }

  async setStatus(state: BridgeState, message: string | null): Promise<void> {
    this.check(await this.db.from('alexa_bridge_status').upsert({
      user_id: this.userId, state, message, last_seen: new Date().toISOString(),
    }));
  }

  async heartbeat(): Promise<void> {
    this.check(await this.db.from('alexa_bridge_status')
      .update({ last_seen: new Date().toISOString() }).eq('user_id', this.userId));
  }
}
```

- [ ] **Step 4: Implementar o gateway real (alexa-remote2)**

Create `bridge/src/alexa-remote-gateway.ts`:
```ts
import { readFile, writeFile } from 'node:fs/promises';
import AlexaRemote from 'alexa-remote2';
import {
  AlexaAuthError, type AlexaGateway, type DeviceAction, type EchoDevice, type Routine, type SmartDevice,
} from './gateway.js';

type Any = any; // eslint-disable-line @typescript-eslint/no-explicit-any

const KNOWN_OPERATIONS = ['turnOn', 'turnOff', 'setBrightness'];
const AUTH_HINT = /401|403|cookie|unauthori[sz]ed|login|csrf/i;

const asError = (err: unknown): Error => {
  const message = String((err as Error)?.message ?? err);
  return AUTH_HINT.test(message) ? new AlexaAuthError(message) : new Error(message);
};

export function mapSmartEntities(raw: unknown): SmartDevice[] {
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((e: Any) => {
    const ops = Array.isArray(e?.supportedOperations)
      ? KNOWN_OPERATIONS.filter((op) => e.supportedOperations.includes(op))
      : [];
    if (typeof e?.id !== 'string' || ops.length === 0) return [];
    return [{ id: e.id, name: String(e.displayName ?? e.id), operations: ops }];
  });
}

export function mapRoutines(raw: unknown): Routine[] {
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((r: Any) => {
    if (typeof r?.automationId !== 'string') return [];
    const utterance = r.triggers?.[0]?.payload?.utterance;
    return [{ id: r.automationId, name: String(r.name ?? utterance ?? 'Rotina sem nome') }];
  });
}

export interface AlexaRemoteOptions {
  cookieFile: string;
  amazonPage: string;
  alexaServiceHost: string;
  language: string;
}

export class AlexaRemoteGateway implements AlexaGateway {
  private readonly alexa: Any = new AlexaRemote();

  static async connect(opts: AlexaRemoteOptions): Promise<AlexaRemoteGateway> {
    let saved: Any;
    try {
      saved = JSON.parse(await readFile(opts.cookieFile, 'utf8'));
    } catch {
      throw new AlexaAuthError(`sem login salvo em ${opts.cookieFile}; rode o login da ponte`);
    }
    const gw = new AlexaRemoteGateway();
    gw.alexa.on('cookie', () => {
      void writeFile(opts.cookieFile, JSON.stringify(gw.alexa.cookieData)).catch(() => {});
    });
    await new Promise<void>((resolve, reject) => {
      gw.alexa.init({
        cookie: saved,
        formerRegistrationData: saved,
        amazonPage: opts.amazonPage,
        alexaServiceHost: opts.alexaServiceHost,
        acceptLanguage: opts.language,
        useWsMqtt: false,
        cookieRefreshInterval: 4 * 24 * 60 * 60 * 1000,
        logger: () => {},
      }, (err: unknown) => (err ? reject(asError(err)) : resolve()));
    });
    return gw;
  }

  private call<T>(method: string, ...args: unknown[]): Promise<T> {
    return new Promise((resolve, reject) => {
      this.alexa[method](...args, (err: unknown, res: T) => (err ? reject(asError(err)) : resolve(res)));
    });
  }

  async listEchos(): Promise<EchoDevice[]> {
    const res = await this.call<Any>('getDevices');
    return (res?.devices ?? [])
      .filter((d: Any) => Array.isArray(d.capabilities) && d.capabilities.includes('VOLUME_SETTING'))
      .map((d: Any) => ({ id: String(d.serialNumber), name: String(d.accountName), online: Boolean(d.online) }));
  }

  async listSmartDevices(): Promise<SmartDevice[]> {
    return mapSmartEntities(await this.call<unknown>('getSmarthomeEntities'));
  }

  async listRoutines(): Promise<Routine[]> {
    return mapRoutines(await this.call<unknown>('getAutomationRoutines'));
  }

  async runRoutine(routineId: string, echoDeviceId: string): Promise<void> {
    const all = await this.call<Any[]>('getAutomationRoutines');
    const routine = (all ?? []).find((r: Any) => r.automationId === routineId);
    if (!routine) throw new Error('rotina não encontrada; sincronize de novo');
    await this.call('executeAutomationRoutine', echoDeviceId, routine);
  }

  async deviceAction(entityId: string, action: DeviceAction, brightness?: number): Promise<void> {
    const parameters: Record<string, unknown> = { action };
    if (action === 'setBrightness') parameters.brightness = brightness;
    await this.call('executeSmarthomeDeviceAction', [entityId], parameters, 'APPLIANCE');
  }

  async speak(echoDeviceId: string, text: string): Promise<void> {
    await this.call('sendSequenceCommand', echoDeviceId, 'speak', text);
  }

  async setVolume(echoDeviceId: string, volume: number): Promise<void> {
    await this.call('sendSequenceCommand', echoDeviceId, 'volume', volume);
  }

  async playSpotify(echoDeviceId: string, query: string): Promise<void> {
    await this.call('playMusicProvider', echoDeviceId, 'SPOTIFY', query);
  }

  async createAlarm(echoDeviceId: string, at: Date, label: string): Promise<string> {
    const notification = this.alexa.createNotificationObject(echoDeviceId, 'Alarm', label, at, 'ON');
    const created = await this.call<Any>('createNotification', notification);
    return JSON.stringify(created && typeof created === 'object' && created.id ? created : notification);
  }

  async deleteAlarm(handle: string): Promise<void> {
    await this.call('deleteNotification', JSON.parse(handle));
  }
}
```

- [ ] **Step 5: Confirmar os nomes dos métodos da versão instalada do alexa-remote2**

Run:
```bash
node -e "const A=require('alexa-remote2');const n=['getDevices','getSmarthomeEntities','getAutomationRoutines','executeAutomationRoutine','executeSmarthomeDeviceAction','sendSequenceCommand','playMusicProvider','createNotificationObject','createNotification','deleteNotification','init'];const p=A.prototype;console.log(n.map(k=>k+': '+(typeof p[k])).join('\n'))"
```
Expected: todos `function`. Se algum estiver `undefined`, abra `node_modules/alexa-remote2/README.md`, ache o método equivalente e ajuste **só** `alexa-remote-gateway.ts`. Os testes não dependem dele.

- [ ] **Step 6: Processo principal e scripts**

Create `bridge/src/main.ts`:
```ts
import { createClient } from '@supabase/supabase-js';
import expressAdapter from 'ask-sdk-express-adapter';
import express from 'express';
import { AlexaRemoteGateway } from './alexa-remote-gateway.js';
import { buildBriefing } from './briefing.js';
import { CommandError, executeCommand, isExpired, type Command } from './commands.js';
import { loadConfig } from './config.js';
import { AlexaAuthError, type AlexaGateway } from './gateway.js';
import { planWakeActions } from './scheduler.js';
import { buildSkill } from './skill.js';
import { SupabaseStore } from './supabase-store.js';
import { addDays, localParts, timeZoneMatches } from './time.js';
import { applyWakeActions, runWake } from './wake.js';

const { ExpressAdapter } = expressAdapter;
const cfg = loadConfig(process.env);
const log = (m: string) => console.log(`[${new Date().toISOString()}] ${m}`);
const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

if (!timeZoneMatches(new Date(), cfg.timeZone)) {
  console.error(`O fuso do processo difere de ${cfg.timeZone}. Defina TZ=${cfg.timeZone}: os alarmes da Alexa usam o horário local do processo.`);
  process.exit(1);
}

const db = createClient(cfg.supabaseUrl, cfg.serviceKey, { auth: { persistSession: false } });
const store = new SupabaseStore(db, cfg.userId, log);
const briefingInput = () => store.briefingInput(new Date(), cfg.timeZone);

// Parte oficial: sobe mesmo se a parte não oficial estiver sem login.
const app = express();
const skill = buildSkill({ allowedUserId: cfg.allowedAlexaUserId, briefingInput, log });
app.post('/alexa', new ExpressAdapter(skill, true, true).getRequestHandlers());
app.get('/health', (_req, res) => { res.json({ ok: true }); });
app.listen(cfg.port, () => log(`ouvindo na porta ${cfg.port}`));

// Parte não oficial
let gateway: AlexaGateway | null = null;
let nextConnectAt = 0;
const inFlight = new Set<string>();
const processing = new Set<string>();

async function handleError(e: unknown, context: string): Promise<void> {
  if (e instanceof AlexaAuthError) {
    gateway = null;
    nextConnectAt = Date.now() + 5 * 60_000;
    await store.setStatus('auth_required', e.message).catch(() => {});
    log(`login da Alexa necessário (${context}): ${e.message}`);
  } else {
    log(`erro em ${context}: ${(e as Error).message}`);
  }
}

async function sync(): Promise<void> {
  if (!gateway) throw new CommandError('ponte sem login na Alexa');
  const [echos, smart, routines] = await Promise.all([
    gateway.listEchos(), gateway.listSmartDevices(), gateway.listRoutines(),
  ]);
  await store.saveDevices(echos, smart);
  await store.saveRoutines(routines);
  log(`sincronizado: ${echos.length} Echos, ${smart.length} dispositivos, ${routines.length} rotinas`);
}

async function ensureGateway(): Promise<AlexaGateway | null> {
  if (gateway || Date.now() < nextConnectAt) return gateway;
  try {
    gateway = await AlexaRemoteGateway.connect({
      cookieFile: cfg.cookieFile, amazonPage: cfg.amazonPage,
      alexaServiceHost: cfg.alexaServiceHost, language: 'pt-BR',
    });
    await store.setStatus('ok', null);
    await sync();
  } catch (e) {
    if (!(e instanceof AlexaAuthError)) {
      nextConnectAt = Date.now() + 60_000;
      await store.setStatus('error', (e as Error).message).catch(() => {});
    }
    await handleError(e, 'conexão');
  }
  return gateway;
}

async function wakeTest(planId: string): Promise<string> {
  const plan = (await store.listWakePlans()).find((p) => p.id === planId);
  if (!plan) throw new CommandError('despertar não encontrado');
  if (!gateway) throw new CommandError('ponte sem login na Alexa');
  const text = buildBriefing(await briefingInput());
  const result = await runWake({ ...plan, briefingDelayMin: 0 }, text, gateway, sleep);
  return result.ok ? 'ok' : `falhou: ${result.notes.join('; ')}`;
}

async function processCommand(cmd: Command): Promise<void> {
  if (processing.has(cmd.id)) return;
  processing.add(cmd.id);
  try {
    if (isExpired(cmd, new Date())) {
      await store.finishCommand(cmd.id, 'expired', 'comando antigo demais; não executado');
      return;
    }
    if (!(await store.claimCommand(cmd.id))) return;
    const gw = await ensureGateway();
    if (!gw) {
      await store.finishCommand(cmd.id, 'failed', 'ponte sem login na Alexa');
      return;
    }
    try {
      await store.finishCommand(cmd.id, 'done', await executeCommand(cmd, { gateway: gw, sync, wakeTest }));
    } catch (e) {
      await handleError(e, `comando ${cmd.kind}`);
      await store.finishCommand(cmd.id, 'failed', (e as Error).message);
    }
  } catch (e) {
    log(`erro ao processar comando ${cmd.id}: ${(e as Error).message}`);
  } finally {
    processing.delete(cmd.id);
  }
}

async function wakeTick(): Promise<void> {
  try {
    const now = new Date();
    const plans = await store.listWakePlans();
    const runs = await store.listWakeRuns(addDays(localParts(now, cfg.timeZone).date, -2));
    const actions = planWakeActions(plans, runs, now, cfg.timeZone);
    if (actions.length === 0) return;
    const gw = await ensureGateway();
    if (!gw) return; // sem login: o alarme reserva já armado toca sozinho
    const running = await applyWakeActions(actions, {
      gateway: gw, store, sleep, log,
      briefing: async () => buildBriefing(await briefingInput()),
    }, inFlight);
    for (const p of running) p.catch((e) => void handleError(e, 'despertar'));
  } catch (e) {
    await handleError(e, 'despertador');
  }
}

store.onNewCommand((cmd) => void processCommand(cmd));
setInterval(() => void store.pendingCommands().then((cmds) => cmds.forEach((c) => void processCommand(c))).catch((e) => log(`fila: ${e.message}`)), 15_000);
setInterval(() => void store.heartbeat().catch((e) => log(`heartbeat: ${e.message}`)), 60_000);
setInterval(() => void (async () => { if (await ensureGateway()) await sync().catch((e) => handleError(e, 'sincronização')); })(), 10 * 60_000);
setInterval(() => void wakeTick(), 30_000);
void ensureGateway().then(() => wakeTick());
```

Create `bridge/src/scripts/login.ts`:
```ts
import { writeFile } from 'node:fs/promises';
import AlexaRemote from 'alexa-remote2';
import { loadConfig } from '../config.js';

const cfg = loadConfig(process.env);
const alexa = new AlexaRemote();

console.log(`Abra http://localhost:${cfg.loginProxyPort} (pelo túnel SSH) e entre na sua conta Amazon.`);
alexa.on('cookie', async () => {
  await writeFile(cfg.cookieFile, JSON.stringify(alexa.cookieData));
  console.log(`Login salvo em ${cfg.cookieFile}. Reinicie a ponte: docker compose restart bridge`);
  process.exit(0);
});
alexa.init({
  proxyOnly: true,
  proxyOwnIp: 'localhost',
  proxyPort: cfg.loginProxyPort,
  proxyListenBind: '0.0.0.0',
  amazonPage: cfg.amazonPage,
  alexaServiceHost: cfg.alexaServiceHost,
  acceptLanguage: 'pt-BR',
  useWsMqtt: false,
  logger: (msg: string) => console.log(msg),
}, (err: unknown) => {
  if (err) console.log(String((err as Error).message ?? err));
});
```

Create `bridge/src/scripts/smoke.ts`:
```ts
import { writeFile } from 'node:fs/promises';
import { AlexaRemoteGateway } from '../alexa-remote-gateway.js';
import { loadConfig } from '../config.js';

const cfg = loadConfig(process.env);
const gw = await AlexaRemoteGateway.connect({
  cookieFile: cfg.cookieFile, amazonPage: cfg.amazonPage, alexaServiceHost: cfg.alexaServiceHost, language: 'pt-BR',
});
const echos = await gw.listEchos();
console.log('Echos:', echos);
console.log('Dispositivos:', await gw.listSmartDevices());
console.log('Rotinas:', await gw.listRoutines());
const [flag, device, ...words] = process.argv.slice(2);
if (flag === '--speak' && device) {
  await gw.speak(device, words.join(' ') || 'Teste da ponte Organizacional.');
  console.log('Falou.');
}
await writeFile('/data/smoke-ok.txt', new Date().toISOString());
process.exit(0);
```

- [ ] **Step 7: Rodar os testes unitários e o build**

Run: `npx vitest run && npm run build`
Expected: todos passam (os de integração aparecem como skipped); `dist/main.js` gerado.

- [ ] **Step 8: Rodar a integração contra o Supabase local**

Run:
```bash
cd /home/only/organizacional && npx supabase start && eval "$(npx supabase status -o env)"
cd bridge && SUPABASE_URL="$API_URL" SUPABASE_SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY" npx vitest run test/supabase-store.test.ts
```
Expected: 5 testes passam, nenhum skipped. Se o CLI não exportar `SERVICE_ROLE_KEY`, copie a service role key de `npx supabase status`.

- [ ] **Step 9: Commit**

```bash
cd /home/only/organizacional
git add bridge
git commit -m "feat(ponte): store Supabase, gateway alexa-remote2 e processo principal"
```

---

### Task 7: Deploy na VPS, login da Alexa e skill no console

**Files:**
- Create: `bridge/Dockerfile`, `bridge/docker-compose.yml`, `bridge/Caddyfile`, `bridge/.env.example`
- Modify: `README.md` (seção Alexa)

**Interfaces:**
- Consumes: Tasks 1–6.
- Produces: ponte rodando em `https://<DOMAIN>` com `/health` e `/alexa`; status `ok` em `alexa_bridge_status`; skill em modo Development na sua conta.

- [ ] **Step 1: Arquivos de deploy**

Create `bridge/Dockerfile`:
```dockerfile
FROM node:22-slim AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
RUN npm run build && npm prune --omit=dev

FROM node:22-slim
RUN apt-get update && apt-get install -y --no-install-recommends tzdata ca-certificates && rm -rf /var/lib/apt/lists/*
ENV NODE_ENV=production TZ=America/Sao_Paulo
WORKDIR /app
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY package.json ./
VOLUME /data
CMD ["node", "dist/main.js"]
```

Create `bridge/docker-compose.yml`:
```yaml
services:
  bridge:
    build: .
    restart: unless-stopped
    env_file: .env
    environment:
      TZ: America/Sao_Paulo
    volumes:
      - ./data:/data
  caddy:
    image: caddy:2
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    environment:
      DOMAIN: ${DOMAIN}
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
volumes:
  caddy_data:
```

Create `bridge/Caddyfile`:
```
{$DOMAIN} {
	reverse_proxy bridge:8080
}
```

Create `bridge/.env.example`:
```
DOMAIN=seu-dominio.duckdns.org
SUPABASE_URL=https://<ref>.supabase.co
SUPABASE_SERVICE_ROLE_KEY=
ORGANIZACIONAL_USER_ID=
ALEXA_ALLOWED_USER_ID=
TZ_NAME=America/Sao_Paulo
ALEXA_COOKIE_FILE=/data/alexa-cookie.json
AMAZON_PAGE=amazon.com.br
ALEXA_SERVICE_HOST=alexa.amazon.com.br
PORT=8080
LOGIN_PROXY_PORT=3001
```

- [ ] **Step 2: Preparar a VPS**

Na VPS (Ubuntu), como usuário com sudo:
```bash
sudo apt-get update && sudo apt-get install -y docker.io docker-compose-v2 git ufw
sudo usermod -aG docker "$USER" && newgrp docker
sudo ufw allow OpenSSH && sudo ufw allow 80 && sudo ufw allow 443 && sudo ufw --force enable
git clone <seu-repositório> organizacional && cd organizacional/bridge
cp .env.example .env && nano .env
```
Preencha o `.env`:
- `DOMAIN`: crie um subdomínio grátis em https://www.duckdns.org apontando para o IP da VPS.
- `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY`: em Project Settings → API.
- `ORGANIZACIONAL_USER_ID`: em Authentication → Users, o UUID do seu usuário.

Rode `npx supabase db push` na sua máquina para aplicar a migration da Task 1 na nuvem.

- [ ] **Step 3: Subir e fazer o login da Alexa**

Run na VPS:
```bash
docker compose build
docker compose run --rm -p 127.0.0.1:3001:3001 bridge node dist/scripts/login.js
```
Na sua máquina: `ssh -L 3001:127.0.0.1:3001 <usuario>@<vps>` e abra http://localhost:3001. Entre na sua conta Amazon (com 2FA, se tiver).
Expected: o comando na VPS imprime `Login salvo em /data/alexa-cookie.json` e termina. Se o login da Amazon Brasil falhar, tente `ALEXA_SERVICE_HOST=pitangui.amazon.com` no `.env` e repita.

Run: `docker compose run --rm bridge node dist/scripts/smoke.js --speak <SERIAL_DO_ECHO> Teste da ponte`
Expected: lista Echos (com `id` = serial), dispositivos e rotinas; o Echo fala "Teste da ponte". Se `Dispositivos` vier vazio mas você tiver lâmpadas na Alexa, salve a resposta crua de `getSmarthomeEntities` como `bridge/test/fixtures/entities.json`, adicione um caso em `mappers.test.ts` com ela e ajuste `mapSmartEntities` até passar.

- [ ] **Step 4: Subir o serviço**

Run: `docker compose up -d && sleep 20 && curl -s https://$DOMAIN/health && docker compose logs --tail=20 bridge`
Expected: `{"ok":true}`; logs com `ouvindo na porta 8080` e `sincronizado: N Echos, ...`. No SQL Editor do Supabase, `select state, last_seen from alexa_bridge_status;` mostra `ok` com horário recente.

- [ ] **Step 5: Criar a skill no console**

Em https://developer.amazon.com/alexa/console/ask:
1. **Create Skill** → nome "Organizacional", idioma **Portuguese (BR)**, modelo **Custom**, hospedagem **Provision your own**, template **Start from scratch**.
2. **Interaction Model → JSON Editor**: cole `bridge/skill/interaction-model.pt-BR.json` → **Save** → **Build skill**.
3. **Endpoint**: HTTPS → `https://<DOMAIN>/alexa`, certificado **"My development endpoint has a certificate from a trusted certificate authority"** → **Save**.
4. **Test**: ative **Development**. Digite "abrir organizacional".
Expected: a skill responde "Skill ainda não configurada..." e o log (`docker compose logs bridge | grep "skill chamada"`) mostra `amzn1.ask.account...`. Copie esse valor para `ALEXA_ALLOWED_USER_ID` no `.env`, rode `docker compose up -d` e teste de novo: o resumo do dia é falado. No Echo: "Alexa, abre organizacional".

- [ ] **Step 6: Documentar e commitar**

Append to `README.md`:
````markdown

## Alexa (ponte na VPS)
- Código em `bridge/`; testes: `cd bridge && npx vitest run` (integração com `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` do Supabase local).
- Subir: `cd bridge && docker compose up -d --build`. Saúde: `https://$DOMAIN/health`.
- **Refazer o login da Alexa** (quando o app avisar):
  1. Na VPS: `docker compose run --rm -p 127.0.0.1:3001:3001 bridge node dist/scripts/login.js`
  2. No seu PC: `ssh -L 3001:127.0.0.1:3001 <usuario>@<vps>` e abra http://localhost:3001
  3. `docker compose restart bridge`
- Diagnóstico: `docker compose run --rm bridge node dist/scripts/smoke.js`.
- Despertares: se a ponte cair, o **alarme reserva** (criado até 24 h antes no próprio Echo) toca 10 min depois do horário.
- Skill: "Alexa, abre organizacional" / "Alexa, pergunte ao organizacional quais são as notícias".
````

```bash
cd /home/only/organizacional
git add bridge/Dockerfile bridge/docker-compose.yml bridge/Caddyfile bridge/.env.example README.md
git commit -m "feat(ponte): deploy com Docker e Caddy e guia de login da Alexa"
```

---

### Task 8: Domínio e repositórios da Alexa no app

**Files:**
- Create: `app/lib/domain/alexa.dart`, `app/lib/data/alexa_repository.dart`, `app/lib/data/memory_alexa_repository.dart`, `app/lib/data/supabase_alexa_repository.dart`
- Test: `app/test/domain/alexa_test.dart`, `app/test/data/memory_alexa_repository_test.dart`

**Interfaces:**
- Consumes: `parseDate`, `newId`, `RepositoryException` (Fase 1); tabelas da Task 1.
- Produces:
  - `enum BridgeState { ok, authRequired, error }`; `class BridgeStatus({required BridgeState state, required DateTime lastSeen, String? message})` + `fromMap`
  - `enum BridgeHealth { unknown, online, offline, authRequired, error }`; `BridgeHealth bridgeHealth(BridgeStatus? s, DateTime now)` (offline após 3 min sem sinal); `String? bridgeBanner(BridgeStatus? s, DateTime now)`; `String? bridgeWarning(BridgeStatus? s, List<WakePlan> plans, DateTime now)`
  - `class AlexaDevice({required String id, required String name, required String kind /* 'echo'|'smart' */, List<String> operations = const [], bool online = true})` + `fromMap`, `supports(String op)`
  - `class AlexaRoutine({required String id, required String name})` + `fromMap`
  - `class WakePlan({required String id, required String label, required List<int> days, required int hour, required int minute, required String echoDeviceId, String? spotifyQuery, bool musicFirst = true, int briefingDelayMin = 3, int volume = 30, bool fallbackAlarm = true, bool enabled = true})` + `fromMap`, `toMap`, `copyWith(...)`, `==`
  - `String? validateWakePlan(WakePlan p)`, `String formatDays(List<int> days)`, `String wakeSummary(WakePlan p, Map<String, String> echoNames)`, `const weekdayShort`, `String twoDigits(int n)`
  - `enum CommandStatus { pending, running, done, failed, expired }`; `class AlexaCommand({required String id, required String kind, required CommandStatus status, String? result})` + `fromMap`, `isFinal`; `String commandOutcome(AlexaCommand? c)`
  - `abstract interface class AlexaRepository { Stream<BridgeStatus?> watchStatus(); Stream<List<AlexaDevice>> watchDevices(); Stream<List<AlexaRoutine>> watchRoutines(); Stream<List<WakePlan>> watchWakePlans(); Future<void> upsertWakePlan(WakePlan plan); Future<void> deleteWakePlan(String id); Future<String> sendCommand(String kind, Map<String, Object?> payload); Stream<AlexaCommand> watchCommand(String id); }`
  - `Future<String> runCommand(AlexaRepository repo, String kind, Map<String, Object?> payload, {Duration timeout = const Duration(seconds: 20)})`
  - `class MemoryAlexaRepository({BridgeStatus? status, List<AlexaDevice> devices, List<AlexaRoutine> routines, List<WakePlan> plans, CommandStatus? respondWith = CommandStatus.done, String? respondResult = 'ok'})` com `sent` (`List<({String kind, Map<String, Object?> payload})>`), `failWrites` e o setter `status`
  - `class SupabaseAlexaRepository(SupabaseClient db)`

- [ ] **Step 1: Escrever os testes**

Create `app/test/domain/alexa_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/alexa.dart';

void main() {
  final now = DateTime(2026, 9, 28, 7);
  BridgeStatus status(BridgeState s, {int minutesAgo = 0, String? message}) =>
      BridgeStatus(state: s, lastSeen: now.subtract(Duration(minutes: minutesAgo)), message: message);
  const plan = WakePlan(
    id: 'p1', label: 'Aula cedo', days: [1, 2, 3, 4, 5], hour: 7, minute: 0,
    echoDeviceId: 'ECHO', spotifyQuery: 'lofi',
  );

  test('bridgeHealth', () {
    expect(bridgeHealth(null, now), BridgeHealth.unknown);
    expect(bridgeHealth(status(BridgeState.ok, minutesAgo: 1), now), BridgeHealth.online);
    expect(bridgeHealth(status(BridgeState.ok, minutesAgo: 4), now), BridgeHealth.offline);
    expect(bridgeHealth(status(BridgeState.authRequired), now), BridgeHealth.authRequired);
    expect(bridgeHealth(status(BridgeState.error, message: 'x'), now), BridgeHealth.error);
  });

  test('bridgeWarning só aparece com despertar ativo', () {
    final expired = status(BridgeState.authRequired);
    expect(bridgeWarning(expired, const [], now), isNull);
    expect(bridgeWarning(expired, [plan.copyWith(enabled: false)], now), isNull);
    expect(bridgeWarning(expired, const [plan], now), startsWith('O login da Alexa expirou'));
    expect(bridgeWarning(status(BridgeState.ok), const [plan], now), isNull);
    expect(bridgeBanner(status(BridgeState.ok, minutesAgo: 10), now),
        'A ponte da Alexa está offline desde 06:50, 28/09. Os despertares vão usar só o alarme reserva.');
  });

  test('formatDays', () {
    expect(formatDays([1, 2, 3, 4, 5]), 'Dias úteis');
    expect(formatDays([7, 6]), 'Fim de semana');
    expect(formatDays([1, 2, 3, 4, 5, 6, 7]), 'Todos os dias');
    expect(formatDays([5, 1, 3]), 'Seg, Qua, Sex');
    expect(formatDays(const []), 'Nenhum dia');
  });

  test('validateWakePlan', () {
    expect(validateWakePlan(plan), isNull);
    expect(validateWakePlan(plan.copyWith(label: '  ')), 'Dê um nome ao despertar.');
    expect(validateWakePlan(plan.copyWith(days: const [])), 'Escolha pelo menos um dia.');
    expect(validateWakePlan(plan.copyWith(echoDeviceId: '')), 'Escolha em qual Echo tocar.');
  });

  test('WakePlan lê o time do Postgres e grava HH:MM; busca vazia vira null', () {
    final read = WakePlan.fromMap({
      'id': 'p1', 'label': 'Aula cedo', 'days': [1, 2, 3, 4, 5], 'time': '07:00:00',
      'echo_device_id': 'ECHO', 'spotify_query': 'lofi', 'music_first': true,
      'briefing_delay_min': 3, 'volume': 30, 'fallback_alarm': true, 'enabled': true,
    });
    expect(read, plan);
    expect(plan.toMap()['time'], '07:00');
    expect(plan.copyWith(spotifyQuery: '').toMap()['spotify_query'], isNull);
  });

  test('wakeSummary', () {
    expect(wakeSummary(plan, {'ECHO': 'Echo do quarto'}), '07:00 · Dias úteis · Echo do quarto · Spotify: lofi');
  });

  test('commandOutcome', () {
    expect(commandOutcome(const AlexaCommand(id: 'c', kind: 'x', status: CommandStatus.done)), 'Feito.');
    expect(commandOutcome(const AlexaCommand(id: 'c', kind: 'x', status: CommandStatus.failed, result: 'sem Spotify')),
        'Falhou: sem Spotify');
    expect(commandOutcome(const AlexaCommand(id: 'c', kind: 'x', status: CommandStatus.expired)),
        'A ponte demorou demais; comando descartado.');
    expect(commandOutcome(null), 'Sem resposta da ponte da Alexa.');
  });
}
```

Create `app/test/data/memory_alexa_repository_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/alexa_repository.dart';
import 'package:organizacional/data/memory_alexa_repository.dart';
import 'package:organizacional/domain/alexa.dart';

void main() {
  test('runCommand devolve o resultado da ponte', () async {
    final repo = MemoryAlexaRepository();
    expect(await runCommand(repo, 'speak', {'text': 'oi'}), 'Feito.');
    expect(repo.sent.single.kind, 'speak');
  });

  test('runCommand com falha da ponte', () async {
    final repo = MemoryAlexaRepository(respondWith: CommandStatus.failed, respondResult: 'rotina não encontrada');
    expect(await runCommand(repo, 'routine', {}), 'Falhou: rotina não encontrada');
  });

  test('runCommand sem resposta dá timeout amigável', () async {
    final repo = MemoryAlexaRepository(respondWith: null);
    expect(await runCommand(repo, 'sync', {}, timeout: const Duration(milliseconds: 20)),
        'Sem resposta da ponte da Alexa.');
  });

  test('watchWakePlans ordena por horário e reflete mudanças', () async {
    const late = WakePlan(id: 'b', label: 'B', days: [1], hour: 9, minute: 0, echoDeviceId: 'E');
    const early = WakePlan(id: 'a', label: 'A', days: [1], hour: 6, minute: 30, echoDeviceId: 'E');
    final repo = MemoryAlexaRepository(plans: const [late]);
    await repo.upsertWakePlan(early);
    expect((await repo.watchWakePlans().first).map((p) => p.id), ['a', 'b']);
    await repo.deleteWakePlan('a');
    expect((await repo.watchWakePlans().first).map((p) => p.id), ['b']);
  });
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd app && TZ=America/Sao_Paulo flutter test test/domain/alexa_test.dart test/data/memory_alexa_repository_test.dart`
Expected: FAIL (arquivos não existem).

- [ ] **Step 3: Implementar o domínio**

Create `app/lib/domain/alexa.dart`:
```dart
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'json.dart';

enum BridgeState { ok, authRequired, error }

class BridgeStatus {
  const BridgeStatus({required this.state, required this.lastSeen, this.message});

  final BridgeState state;
  final DateTime lastSeen;
  final String? message;

  factory BridgeStatus.fromMap(Map<String, dynamic> m) => BridgeStatus(
        state: switch (m['state']) {
          'auth_required' => BridgeState.authRequired,
          'error' => BridgeState.error,
          _ => BridgeState.ok,
        },
        lastSeen: parseDate(m['last_seen'])!,
        message: m['message'] as String?,
      );
}

enum BridgeHealth { unknown, online, offline, authRequired, error }

const bridgeOfflineAfter = Duration(minutes: 3);

BridgeHealth bridgeHealth(BridgeStatus? s, DateTime now) {
  if (s == null) return BridgeHealth.unknown;
  if (now.difference(s.lastSeen) > bridgeOfflineAfter) return BridgeHealth.offline;
  return switch (s.state) {
    BridgeState.ok => BridgeHealth.online,
    BridgeState.authRequired => BridgeHealth.authRequired,
    BridgeState.error => BridgeHealth.error,
  };
}

String? bridgeBanner(BridgeStatus? s, DateTime now) => switch (bridgeHealth(s, now)) {
      BridgeHealth.online => null,
      BridgeHealth.unknown => 'A ponte da Alexa ainda não se conectou.',
      BridgeHealth.offline =>
        'A ponte da Alexa está offline desde ${DateFormat('HH:mm, dd/MM', 'pt_BR').format(s!.lastSeen)}. '
            'Os despertares vão usar só o alarme reserva.',
      BridgeHealth.authRequired =>
        'O login da Alexa expirou. Refaça o login na ponte (README, seção Alexa).',
      BridgeHealth.error => 'Erro na ponte da Alexa: ${s!.message ?? 'desconhecido'}',
    };

String? bridgeWarning(BridgeStatus? s, List<WakePlan> plans, DateTime now) =>
    plans.any((p) => p.enabled) ? bridgeBanner(s, now) : null;

class AlexaDevice {
  const AlexaDevice({
    required this.id,
    required this.name,
    required this.kind,
    this.operations = const [],
    this.online = true,
  });

  final String id;
  final String name;
  final String kind;
  final List<String> operations;
  final bool online;

  bool supports(String op) => operations.contains(op);

  factory AlexaDevice.fromMap(Map<String, dynamic> m) => AlexaDevice(
        id: m['id'] as String,
        name: m['name'] as String,
        kind: m['kind'] as String,
        operations: ((m['operations'] as List?) ?? const []).cast<String>(),
        online: (m['online'] as bool?) ?? true,
      );
}

class AlexaRoutine {
  const AlexaRoutine({required this.id, required this.name});

  final String id;
  final String name;

  factory AlexaRoutine.fromMap(Map<String, dynamic> m) =>
      AlexaRoutine(id: m['id'] as String, name: m['name'] as String);
}

const weekdayShort = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

String twoDigits(int n) => n.toString().padLeft(2, '0');

class WakePlan {
  const WakePlan({
    required this.id,
    required this.label,
    required this.days,
    required this.hour,
    required this.minute,
    required this.echoDeviceId,
    this.spotifyQuery,
    this.musicFirst = true,
    this.briefingDelayMin = 3,
    this.volume = 30,
    this.fallbackAlarm = true,
    this.enabled = true,
  });

  final String id;
  final String label;
  final List<int> days;
  final int hour;
  final int minute;
  final String echoDeviceId;
  final String? spotifyQuery;
  final bool musicFirst;
  final int briefingDelayMin;
  final int volume;
  final bool fallbackAlarm;
  final bool enabled;

  factory WakePlan.fromMap(Map<String, dynamic> m) {
    final time = (m['time'] as String).split(':');
    return WakePlan(
      id: m['id'] as String,
      label: m['label'] as String,
      days: ((m['days'] as List?) ?? const []).map((d) => (d as num).toInt()).toList(),
      hour: int.parse(time[0]),
      minute: int.parse(time[1]),
      echoDeviceId: m['echo_device_id'] as String,
      spotifyQuery: m['spotify_query'] as String?,
      musicFirst: (m['music_first'] as bool?) ?? true,
      briefingDelayMin: (m['briefing_delay_min'] as num?)?.toInt() ?? 3,
      volume: (m['volume'] as num?)?.toInt() ?? 30,
      fallbackAlarm: (m['fallback_alarm'] as bool?) ?? true,
      enabled: (m['enabled'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    final query = spotifyQuery?.trim();
    return {
      'id': id,
      'label': label,
      'days': days,
      'time': '${twoDigits(hour)}:${twoDigits(minute)}',
      'echo_device_id': echoDeviceId,
      'spotify_query': (query == null || query.isEmpty) ? null : query,
      'music_first': musicFirst,
      'briefing_delay_min': briefingDelayMin,
      'volume': volume,
      'fallback_alarm': fallbackAlarm,
      'enabled': enabled,
    };
  }

  WakePlan copyWith({
    String? label,
    List<int>? days,
    int? hour,
    int? minute,
    String? echoDeviceId,
    String? spotifyQuery,
    bool? musicFirst,
    int? briefingDelayMin,
    int? volume,
    bool? fallbackAlarm,
    bool? enabled,
  }) =>
      WakePlan(
        id: id,
        label: label ?? this.label,
        days: days ?? this.days,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        echoDeviceId: echoDeviceId ?? this.echoDeviceId,
        spotifyQuery: spotifyQuery ?? this.spotifyQuery,
        musicFirst: musicFirst ?? this.musicFirst,
        briefingDelayMin: briefingDelayMin ?? this.briefingDelayMin,
        volume: volume ?? this.volume,
        fallbackAlarm: fallbackAlarm ?? this.fallbackAlarm,
        enabled: enabled ?? this.enabled,
      );

  @override
  bool operator ==(Object other) =>
      other is WakePlan &&
      other.id == id &&
      other.label == label &&
      listEquals(other.days, days) &&
      other.hour == hour &&
      other.minute == minute &&
      other.echoDeviceId == echoDeviceId &&
      other.spotifyQuery == spotifyQuery &&
      other.musicFirst == musicFirst &&
      other.briefingDelayMin == briefingDelayMin &&
      other.volume == volume &&
      other.fallbackAlarm == fallbackAlarm &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(id, label, Object.hashAll(days), hour, minute, echoDeviceId,
      spotifyQuery, musicFirst, briefingDelayMin, volume, fallbackAlarm, enabled);
}

String? validateWakePlan(WakePlan p) {
  if (p.label.trim().isEmpty) return 'Dê um nome ao despertar.';
  if (p.days.isEmpty) return 'Escolha pelo menos um dia.';
  if (p.echoDeviceId.isEmpty) return 'Escolha em qual Echo tocar.';
  return null;
}

String formatDays(List<int> days) {
  final set = days.toSet();
  if (set.isEmpty) return 'Nenhum dia';
  if (set.length == 7) return 'Todos os dias';
  if (setEquals(set, {1, 2, 3, 4, 5})) return 'Dias úteis';
  if (setEquals(set, {6, 7})) return 'Fim de semana';
  return (set.toList()..sort()).map((d) => weekdayShort[d - 1]).join(', ');
}

String wakeSummary(WakePlan p, Map<String, String> echoNames) {
  final query = p.spotifyQuery?.trim() ?? '';
  return [
    '${twoDigits(p.hour)}:${twoDigits(p.minute)}',
    formatDays(p.days),
    if (echoNames[p.echoDeviceId] != null) echoNames[p.echoDeviceId]!,
    if (query.isNotEmpty) 'Spotify: $query',
  ].join(' · ');
}

enum CommandStatus { pending, running, done, failed, expired }

class AlexaCommand {
  const AlexaCommand({required this.id, required this.kind, required this.status, this.result});

  final String id;
  final String kind;
  final CommandStatus status;
  final String? result;

  bool get isFinal =>
      status == CommandStatus.done || status == CommandStatus.failed || status == CommandStatus.expired;

  factory AlexaCommand.fromMap(Map<String, dynamic> m) => AlexaCommand(
        id: m['id'] as String,
        kind: m['kind'] as String,
        status: CommandStatus.values.byName(m['status'] as String),
        result: m['result'] as String?,
      );
}

String commandOutcome(AlexaCommand? c) => switch (c?.status) {
      CommandStatus.done => 'Feito.',
      CommandStatus.failed => 'Falhou: ${c!.result ?? 'erro desconhecido'}',
      CommandStatus.expired => 'A ponte demorou demais; comando descartado.',
      _ => 'Sem resposta da ponte da Alexa.',
    };
```

- [ ] **Step 4: Implementar os repositórios**

Create `app/lib/data/alexa_repository.dart`:
```dart
import 'dart:async';

import '../domain/alexa.dart';

abstract interface class AlexaRepository {
  Stream<BridgeStatus?> watchStatus();
  Stream<List<AlexaDevice>> watchDevices();
  Stream<List<AlexaRoutine>> watchRoutines();
  Stream<List<WakePlan>> watchWakePlans();
  Future<void> upsertWakePlan(WakePlan plan);
  Future<void> deleteWakePlan(String id);

  /// Enfileira um comando para a ponte e devolve o id.
  Future<String> sendCommand(String kind, Map<String, Object?> payload);
  Stream<AlexaCommand> watchCommand(String id);
}

/// Envia o comando e espera a ponte concluir; devolve uma frase para o usuário.
Future<String> runCommand(
  AlexaRepository repo,
  String kind,
  Map<String, Object?> payload, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final id = await repo.sendCommand(kind, payload);
  try {
    final cmd = await repo.watchCommand(id).firstWhere((c) => c.isFinal).timeout(timeout);
    return commandOutcome(cmd);
  } on TimeoutException {
    return commandOutcome(null);
  }
}
```

Create `app/lib/data/memory_alexa_repository.dart`:
```dart
import 'dart:async';

import '../domain/alexa.dart';
import '../domain/ids.dart';
import 'alexa_repository.dart';
import 'repository.dart';

/// Implementação em memória para testes; simula a ponte respondendo aos comandos.
class MemoryAlexaRepository implements AlexaRepository {
  MemoryAlexaRepository({
    BridgeStatus? status,
    List<AlexaDevice> devices = const [],
    List<AlexaRoutine> routines = const [],
    List<WakePlan> plans = const [],
    this.respondWith = CommandStatus.done,
    this.respondResult = 'ok',
  })  : _status = status,
        _devices = [...devices],
        _routines = [...routines],
        _plans = {for (final p in plans) p.id: p};

  BridgeStatus? _status;
  final List<AlexaDevice> _devices;
  final List<AlexaRoutine> _routines;
  final Map<String, WakePlan> _plans;
  final CommandStatus? respondWith;
  final String? respondResult;
  final sent = <({String kind, Map<String, Object?> payload})>[];
  final _commands = <String, AlexaCommand>{};
  final _changes = StreamController<void>.broadcast(sync: true);
  bool failWrites = false;

  set status(BridgeStatus? value) {
    _status = value;
    _changes.add(null);
  }

  Stream<T> _watch<T>(T Function() snapshot) {
    StreamSubscription<void>? sub;
    late final StreamController<T> controller;
    controller = StreamController<T>(
      onListen: () {
        controller.add(snapshot());
        sub = _changes.stream.listen((_) => controller.add(snapshot()));
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  void _checkWrite() {
    if (failWrites) throw const RepositoryException('Sem conexão (simulado)');
  }

  @override
  Stream<BridgeStatus?> watchStatus() => _watch(() => _status);

  @override
  Stream<List<AlexaDevice>> watchDevices() => _watch(() => List.of(_devices));

  @override
  Stream<List<AlexaRoutine>> watchRoutines() => _watch(() => List.of(_routines));

  @override
  Stream<List<WakePlan>> watchWakePlans() => _watch(() => _plans.values.toList()
    ..sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute)));

  @override
  Future<void> upsertWakePlan(WakePlan plan) async {
    _checkWrite();
    _plans[plan.id] = plan;
    _changes.add(null);
  }

  @override
  Future<void> deleteWakePlan(String id) async {
    _checkWrite();
    _plans.remove(id);
    _changes.add(null);
  }

  @override
  Future<String> sendCommand(String kind, Map<String, Object?> payload) async {
    _checkWrite();
    final id = newId();
    sent.add((kind: kind, payload: payload));
    _commands[id] = AlexaCommand(id: id, kind: kind, status: CommandStatus.pending);
    _changes.add(null);
    final respond = respondWith;
    if (respond != null) {
      scheduleMicrotask(() {
        _commands[id] = AlexaCommand(id: id, kind: kind, status: respond, result: respondResult);
        _changes.add(null);
      });
    }
    return id;
  }

  @override
  Stream<AlexaCommand> watchCommand(String id) =>
      _watch(() => _commands[id]).where((c) => c != null).cast<AlexaCommand>();
}
```

Create `app/lib/data/supabase_alexa_repository.dart`:
```dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/alexa.dart';
import 'alexa_repository.dart';
import 'repository.dart';

class SupabaseAlexaRepository implements AlexaRepository {
  SupabaseAlexaRepository(this._db);

  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on PostgrestException catch (e) {
      throw RepositoryException(e.message, duplicate: e.code == '23505');
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException('Falha de conexão: $e');
    }
  }

  @override
  Stream<BridgeStatus?> watchStatus() => _db
      .from('alexa_bridge_status')
      .stream(primaryKey: ['user_id'])
      .map((rows) => rows.isEmpty ? null : BridgeStatus.fromMap(rows.first));

  @override
  Stream<List<AlexaDevice>> watchDevices() => _db
      .from('alexa_devices')
      .stream(primaryKey: ['user_id', 'id'])
      .order('name', ascending: true)
      .map((rows) => rows.map(AlexaDevice.fromMap).toList());

  @override
  Stream<List<AlexaRoutine>> watchRoutines() => _db
      .from('alexa_routines')
      .stream(primaryKey: ['user_id', 'id'])
      .order('name', ascending: true)
      .map((rows) => rows.map(AlexaRoutine.fromMap).toList());

  @override
  Stream<List<WakePlan>> watchWakePlans() => _db
      .from('wake_plans')
      .stream(primaryKey: ['id'])
      .order('time', ascending: true)
      .map((rows) => rows.map(WakePlan.fromMap).toList());

  @override
  Future<void> upsertWakePlan(WakePlan plan) =>
      _guard(() async => await _db.from('wake_plans').upsert(plan.toMap()));

  @override
  Future<void> deleteWakePlan(String id) =>
      _guard(() async => await _db.from('wake_plans').delete().eq('id', id));

  @override
  Future<String> sendCommand(String kind, Map<String, Object?> payload) => _guard(() async {
        final row = await _db
            .from('alexa_commands')
            .insert({'kind': kind, 'payload': payload})
            .select('id')
            .single();
        return row['id'] as String;
      });

  @override
  Stream<AlexaCommand> watchCommand(String id) => _db
      .from('alexa_commands')
      .stream(primaryKey: ['id'])
      .eq('id', id)
      .where((rows) => rows.isNotEmpty)
      .map((rows) => AlexaCommand.fromMap(rows.first));
}
```

- [ ] **Step 5: Rodar e ver passar**

Run: `TZ=America/Sao_Paulo flutter test --exclude-tags integration && flutter analyze`
Expected: `All tests passed!`; sem erros nem warnings.

- [ ] **Step 6: Commit**

```bash
cd /home/only/organizacional
git add app/lib/domain/alexa.dart app/lib/data/alexa_repository.dart app/lib/data/memory_alexa_repository.dart app/lib/data/supabase_alexa_repository.dart app/test/domain/alexa_test.dart app/test/data/memory_alexa_repository_test.dart
git commit -m "feat: domínio e repositórios da Alexa no app"
```

---

### Task 9: Telas Casa e Despertar, aviso em Hoje e rotas

**Files:**
- Create: `app/lib/features/home/home_screen.dart`, `app/lib/features/home/wake_plan_screen.dart`
- Modify: `app/lib/app/providers.dart`, `app/lib/app/router.dart`
- Replace: `app/lib/features/today/today_screen.dart`, `app/lib/main.dart`, `app/test/helpers.dart`
- Test: `app/test/features/home_test.dart`

**Interfaces:**
- Consumes: Task 8 inteira; Fases 1–2 (providers, `NewsTile`, `newsFeedProvider`, widgets comuns, `buildDayAgenda`, `startOfDay`).
- Produces:
  - Providers: `alexaRepositoryProvider`, `bridgeStatusProvider` (`StreamProvider<BridgeStatus?>`), `alexaDevicesProvider`, `alexaRoutinesProvider`, `wakePlansProvider`
  - Rotas `/casa` → `HomeScreen`, `/casa/despertar/:id` → `WakePlanScreen(planId:)` (`novo` = criar)
  - Keys: `open-home`, `bridge-warning` (Hoje); `bridge-banner`, `sync-alexa`, `new-wake`, `wake-enabled-<id>`, `run-routine-<id>`, `on-<id>`, `off-<id>`, `brightness-<id>`, `speak-text`, `speak-send`, `echo-<id>` (Casa); `wake-label`, `wake-time`, `day-<1..7>`, `wake-spotify`, `wake-fallback`, `wake-error`, `wake-save`, `wake-test`, `wake-delete` (Despertar)
  - `pumpApp(..., AlexaRepository? alexa)`

- [ ] **Step 1: Atualizar o helper e escrever os testes**

Replace all of `app/test/helpers.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/app/app.dart';
import 'package:organizacional/app/providers.dart';
import 'package:organizacional/app/router.dart';
import 'package:organizacional/data/alexa_repository.dart';
import 'package:organizacional/data/memory_alexa_repository.dart';
import 'package:organizacional/data/memory_news_repository.dart';
import 'package:organizacional/data/news_repository.dart';
import 'package:organizacional/data/repository.dart';

final defaultNow = DateTime(2026, 9, 28, 10); // segunda-feira

Future<void> pumpApp(
  WidgetTester tester,
  Repository repo, {
  String location = '/',
  DateTime? now,
  Size size = const Size(1000, 800),
  NewsRepository? news,
  Future<void> Function(Uri)? openLink,
  AlexaRepository? alexa,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      clockProvider.overrideWithValue(() => now ?? defaultNow),
      newsRepositoryProvider.overrideWithValue(news ?? MemoryNewsRepository()),
      linkOpenerProvider.overrideWithValue(openLink ?? (_) async {}),
      alexaRepositoryProvider.overrideWithValue(alexa ?? MemoryAlexaRepository()),
    ],
    child: OrganizacionalApp(
      router: buildRouter(initialLocation: location, isSignedIn: () => true),
    ),
  ));
  await tester.pumpAndSettle();
}
```

Create `app/test/features/home_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_alexa_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/alexa.dart';

import '../helpers.dart';

const _tall = Size(1000, 1800);
final _now = DateTime(2026, 9, 28, 10);
const _plan = WakePlan(
  id: 'p1', label: 'Aula cedo', days: [1, 2, 3, 4, 5], hour: 7, minute: 0,
  echoDeviceId: 'ECHO', spotifyQuery: 'lofi',
);

MemoryAlexaRepository _alexa({
  BridgeState state = BridgeState.ok,
  int minutesAgo = 0,
  List<WakePlan> plans = const [_plan],
  CommandStatus? respondWith = CommandStatus.done,
  String? respondResult = 'ok',
}) =>
    MemoryAlexaRepository(
      status: BridgeStatus(state: state, lastSeen: _now.subtract(Duration(minutes: minutesAgo))),
      devices: const [
        AlexaDevice(id: 'ECHO', name: 'Echo do quarto', kind: 'echo'),
        AlexaDevice(id: 'luz1', name: 'Luz do quarto', kind: 'smart', operations: ['turnOn', 'turnOff', 'setBrightness']),
      ],
      routines: const [AlexaRoutine(id: 'r1', name: 'Boa noite')],
      plans: plans,
      respondWith: respondWith,
      respondResult: respondResult,
    );

void main() {
  testWidgets('Casa lista despertares, rotinas e dispositivos; sem aviso com a ponte online', (tester) async {
    await pumpApp(tester, MemoryRepository(), location: '/casa', now: _now, alexa: _alexa(), size: _tall);
    expect(find.text('Aula cedo'), findsOneWidget);
    expect(find.text('07:00 · Dias úteis · Echo do quarto · Spotify: lofi'), findsOneWidget);
    expect(find.text('Boa noite'), findsOneWidget);
    expect(find.text('Luz do quarto'), findsOneWidget);
    expect(find.byKey(const Key('bridge-banner')), findsNothing);
  });

  testWidgets('ponte offline mostra aviso em Casa', (tester) async {
    await pumpApp(tester, MemoryRepository(), location: '/casa', now: _now, alexa: _alexa(minutesAgo: 10), size: _tall);
    expect(find.byKey(const Key('bridge-banner')), findsOneWidget);
    expect(find.textContaining('offline desde 09:50'), findsOneWidget);
  });

  testWidgets('executar rotina envia o Echo escolhido e mostra o resultado', (tester) async {
    final alexa = _alexa();
    await pumpApp(tester, MemoryRepository(), location: '/casa', now: _now, alexa: alexa, size: _tall);
    await tester.tap(find.byKey(const ValueKey('run-routine-r1')));
    await tester.pumpAndSettle();
    expect(alexa.sent.single.kind, 'routine');
    expect(alexa.sent.single.payload, {'routineId': 'r1', 'echoDeviceId': 'ECHO'});
    expect(find.text('Feito.'), findsOneWidget);
  });

  testWidgets('falha da ponte aparece para o usuário', (tester) async {
    final alexa = _alexa(respondWith: CommandStatus.failed, respondResult: 'rotina não encontrada');
    await pumpApp(tester, MemoryRepository(), location: '/casa', now: _now, alexa: alexa, size: _tall);
    await tester.tap(find.byKey(const ValueKey('run-routine-r1')));
    await tester.pumpAndSettle();
    expect(find.text('Falhou: rotina não encontrada'), findsOneWidget);
  });

  testWidgets('ligar dispositivo e falar no Echo', (tester) async {
    final alexa = _alexa();
    await pumpApp(tester, MemoryRepository(), location: '/casa', now: _now, alexa: alexa, size: _tall);
    await tester.tap(find.byKey(const ValueKey('on-luz1')));
    await tester.pumpAndSettle();
    expect(alexa.sent.last.payload, {'entityId': 'luz1', 'action': 'turnOn'});
    await tester.enterText(find.byKey(const Key('speak-text')), 'o jantar está pronto');
    await tester.tap(find.byKey(const Key('speak-send')));
    await tester.pumpAndSettle();
    expect(alexa.sent.last.kind, 'speak');
    expect(alexa.sent.last.payload, {'echoDeviceId': 'ECHO', 'text': 'o jantar está pronto'});
  });

  testWidgets('desativar despertar pelo switch', (tester) async {
    final alexa = _alexa();
    await pumpApp(tester, MemoryRepository(), location: '/casa', now: _now, alexa: alexa, size: _tall);
    await tester.tap(find.byKey(const ValueKey('wake-enabled-p1')));
    await tester.pumpAndSettle();
    expect((await alexa.watchWakePlans().first).single.enabled, isFalse);
  });

  testWidgets('novo despertar valida dias e salva', (tester) async {
    final alexa = _alexa(plans: const []);
    await pumpApp(tester, MemoryRepository(), location: '/casa/despertar/novo', now: _now, alexa: alexa, size: _tall);
    await tester.enterText(find.byKey(const Key('wake-label')), 'Academia');
    for (var d = 1; d <= 5; d++) {
      await tester.tap(find.byKey(ValueKey('day-$d')));
    }
    await tester.pump();
    await tester.tap(find.byKey(const Key('wake-save')));
    await tester.pump();
    expect(find.text('Escolha pelo menos um dia.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('day-6')));
    await tester.enterText(find.byKey(const Key('wake-spotify')), 'rock');
    await tester.tap(find.byKey(const Key('wake-save')));
    await tester.pumpAndSettle();
    final saved = (await alexa.watchWakePlans().first).single;
    expect(saved.label, 'Academia');
    expect(saved.days, [6]);
    expect(saved.echoDeviceId, 'ECHO');
    expect(saved.spotifyQuery, 'rock');
    expect(find.text('Academia'), findsOneWidget); // voltou para Casa
  });

  testWidgets('Hoje avisa login expirado quando há despertar ativo e abre Casa', (tester) async {
    await pumpApp(tester, MemoryRepository(), now: _now, alexa: _alexa(state: BridgeState.authRequired));
    expect(find.byKey(const Key('bridge-warning')), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-home')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Casa'), findsOneWidget);
  });

  testWidgets('Hoje sem despertar ativo não mostra aviso', (tester) async {
    await pumpApp(tester, MemoryRepository(), now: _now, alexa: _alexa(state: BridgeState.authRequired, plans: const []));
    expect(find.byKey(const Key('bridge-warning')), findsNothing);
  });
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd app && TZ=America/Sao_Paulo flutter test test/features/home_test.dart`
Expected: FAIL (`alexaRepositoryProvider` não definido).

- [ ] **Step 3: Providers e rotas**

Modify `app/lib/app/providers.dart`, adding the imports:
```dart
import '../data/alexa_repository.dart';
import '../domain/alexa.dart';
```
and appending:
```dart
final alexaRepositoryProvider = Provider<AlexaRepository>(
  (ref) => throw UnimplementedError('alexaRepositoryProvider precisa de override'),
);

final bridgeStatusProvider =
    StreamProvider<BridgeStatus?>((ref) => ref.watch(alexaRepositoryProvider).watchStatus());

final alexaDevicesProvider =
    StreamProvider<List<AlexaDevice>>((ref) => ref.watch(alexaRepositoryProvider).watchDevices());

final alexaRoutinesProvider =
    StreamProvider<List<AlexaRoutine>>((ref) => ref.watch(alexaRepositoryProvider).watchRoutines());

final wakePlansProvider =
    StreamProvider<List<WakePlan>>((ref) => ref.watch(alexaRepositoryProvider).watchWakePlans());
```

Modify `app/lib/app/router.dart`: add the imports
```dart
import '../features/home/home_screen.dart';
import '../features/home/wake_plan_screen.dart';
```
and, inside the `ShellRoute` `routes: [...]`, after `/noticias/ajustes`:
```dart
            GoRoute(path: '/casa', builder: (context, state) => const HomeScreen()),
            GoRoute(
              path: '/casa/despertar/:id',
              builder: (context, state) {
                final id = state.pathParameters['id']!;
                return WakePlanScreen(key: ValueKey('wake-$id'), planId: id);
              },
            ),
```

- [ ] **Step 4: Tela Casa**

Create `app/lib/features/home/home_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/alexa_repository.dart';
import '../../data/repository.dart';
import '../../domain/alexa.dart';
import '../../ui/common.dart';

typedef SendCommand = Future<void> Function(String kind, Map<String, Object?> payload);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _speech = TextEditingController();
  String? _echoId;

  @override
  void dispose() {
    _speech.dispose();
    super.dispose();
  }

  Future<void> _send(String kind, Map<String, Object?> payload) async {
    try {
      final outcome = await runCommand(ref.read(alexaRepositoryProvider), kind, payload);
      if (mounted) showError(context, outcome);
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível enviar o comando.');
    }
  }

  Future<void> _toggle(WakePlan plan, bool enabled) async {
    try {
      await ref.read(alexaRepositoryProvider).upsertWakePlan(plan.copyWith(enabled: enabled));
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível alterar o despertar.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = ref.watch(clockProvider)();
    final status = ref.watch(bridgeStatusProvider).value;
    final devices = ref.watch(alexaDevicesProvider).value ?? const <AlexaDevice>[];
    final routines = ref.watch(alexaRoutinesProvider).value ?? const <AlexaRoutine>[];
    final plans = ref.watch(wakePlansProvider).value ?? const <WakePlan>[];
    final echos = devices.where((d) => d.kind == 'echo').toList();
    final smart = devices.where((d) => d.kind == 'smart').toList();
    final echoId = _echoId ?? echos.where((e) => e.online).firstOrNull?.id ?? echos.firstOrNull?.id;
    final names = {for (final e in echos) e.id: e.name};
    final banner = bridgeBanner(status, now);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Casa'),
        actions: [
          IconButton(
            key: const Key('sync-alexa'),
            tooltip: 'Sincronizar com a Alexa',
            icon: const Icon(Icons.sync),
            onPressed: () => _send('sync', const {}),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (banner != null)
            Card(
              key: const Key('bridge-banner'),
              color: theme.colorScheme.errorContainer,
              child: Padding(padding: const EdgeInsets.all(16), child: Text(banner)),
            ),
          if (echos.isNotEmpty) ...[
            const SectionHeader('Tocar em'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in echos)
                  ChoiceChip(
                    key: ValueKey('echo-${e.id}'),
                    label: Text(e.online ? e.name : '${e.name} (offline)'),
                    selected: e.id == echoId,
                    onSelected: (_) => setState(() => _echoId = e.id),
                  ),
              ],
            ),
          ],
          Row(
            children: [
              const Expanded(child: SectionHeader('Despertar')),
              TextButton.icon(
                key: const Key('new-wake'),
                onPressed: () => context.go('/casa/despertar/novo'),
                icon: const Icon(Icons.add),
                label: const Text('Novo'),
              ),
            ],
          ),
          if (plans.isEmpty) const EmptyHint('Nenhum despertar. Crie um para tocar Spotify e ouvir seu dia.'),
          for (final p in plans)
            ListTile(
              leading: const Icon(Icons.alarm),
              title: Text(p.label),
              subtitle: Text(wakeSummary(p, names)),
              trailing: Switch(
                key: ValueKey('wake-enabled-${p.id}'),
                value: p.enabled,
                onChanged: (v) => _toggle(p, v),
              ),
              onTap: () => context.go('/casa/despertar/${p.id}'),
            ),
          const SectionHeader('Rotinas da Alexa'),
          if (routines.isEmpty) const EmptyHint('Nenhuma rotina sincronizada.'),
          for (final r in routines)
            ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: Text(r.name),
              trailing: IconButton(
                key: ValueKey('run-routine-${r.id}'),
                tooltip: 'Executar',
                icon: const Icon(Icons.play_arrow),
                onPressed: echoId == null
                    ? null
                    : () => _send('routine', {'routineId': r.id, 'echoDeviceId': echoId}),
              ),
            ),
          const SectionHeader('Dispositivos'),
          if (smart.isEmpty) const EmptyHint('Nenhum dispositivo inteligente encontrado.'),
          for (final d in smart) _DeviceTile(key: ValueKey('device-${d.id}'), device: d, onCommand: _send),
          const SectionHeader('Falar no Echo'),
          TextField(
            key: const Key('speak-text'),
            controller: _speech,
            decoration: InputDecoration(
              hintText: 'Ex.: o jantar está pronto',
              suffixIcon: IconButton(
                key: const Key('speak-send'),
                tooltip: 'Falar',
                icon: const Icon(Icons.campaign_outlined),
                onPressed: echoId == null
                    ? null
                    : () {
                        final text = _speech.text.trim();
                        if (text.isEmpty) return;
                        _speech.clear();
                        _send('speak', {'echoDeviceId': echoId, 'text': text});
                      },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatefulWidget {
  const _DeviceTile({super.key, required this.device, required this.onCommand});

  final AlexaDevice device;
  final SendCommand onCommand;

  @override
  State<_DeviceTile> createState() => _DeviceTileState();
}

class _DeviceTileState extends State<_DeviceTile> {
  double _brightness = 50;

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.lightbulb_outline),
          title: Text(d.name),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (d.supports('turnOff'))
                IconButton(
                  key: ValueKey('off-${d.id}'),
                  tooltip: 'Desligar',
                  icon: const Icon(Icons.power_settings_new),
                  onPressed: () => widget.onCommand('device', {'entityId': d.id, 'action': 'turnOff'}),
                ),
              if (d.supports('turnOn'))
                IconButton(
                  key: ValueKey('on-${d.id}'),
                  tooltip: 'Ligar',
                  icon: const Icon(Icons.power),
                  onPressed: () => widget.onCommand('device', {'entityId': d.id, 'action': 'turnOn'}),
                ),
            ],
          ),
        ),
        if (d.supports('setBrightness'))
          Slider(
            key: ValueKey('brightness-${d.id}'),
            value: _brightness,
            max: 100,
            divisions: 10,
            label: '${_brightness.round()}%',
            onChanged: (v) => setState(() => _brightness = v),
            onChangeEnd: (v) => widget.onCommand(
              'device',
              {'entityId': d.id, 'action': 'setBrightness', 'brightness': v.round()},
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 5: Tela do despertar**

Create `app/lib/features/home/wake_plan_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/alexa_repository.dart';
import '../../data/repository.dart';
import '../../domain/alexa.dart';
import '../../domain/ids.dart';
import '../../ui/common.dart';

class WakePlanScreen extends ConsumerStatefulWidget {
  const WakePlanScreen({super.key, required this.planId});

  /// "novo" cria um despertar.
  final String planId;

  @override
  ConsumerState<WakePlanScreen> createState() => _WakePlanScreenState();
}

class _WakePlanScreenState extends ConsumerState<WakePlanScreen> {
  final _label = TextEditingController();
  final _spotify = TextEditingController();
  WakePlan? _draft;
  String? _error;

  bool get _isNew => widget.planId == 'novo';

  @override
  void dispose() {
    _label.dispose();
    _spotify.dispose();
    super.dispose();
  }

  WakePlan _initial(List<WakePlan> plans, List<AlexaDevice> echos) {
    if (!_isNew) {
      final existing = plans.where((p) => p.id == widget.planId).firstOrNull;
      if (existing != null) return existing;
    }
    return WakePlan(
      id: newId(),
      label: 'Despertar',
      days: const [1, 2, 3, 4, 5],
      hour: 7,
      minute: 0,
      echoDeviceId: echos.where((e) => e.online).firstOrNull?.id ?? echos.firstOrNull?.id ?? '',
    );
  }

  void _update(WakePlan Function(WakePlan d) change) => setState(() => _draft = change(_draft!));

  Future<void> _pickTime() async {
    final d = _draft!;
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: d.hour, minute: d.minute));
    if (picked != null) _update((d) => d.copyWith(hour: picked.hour, minute: picked.minute));
  }

  Future<void> _save() async {
    final plan = _draft!.copyWith(label: _label.text.trim(), spotifyQuery: _spotify.text.trim());
    final problem = validateWakePlan(plan);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    try {
      await ref.read(alexaRepositoryProvider).upsertWakePlan(plan);
      if (mounted) context.go('/casa');
    } on RepositoryException {
      if (mounted) setState(() => _error = 'Não foi possível salvar.');
    }
  }

  Future<void> _test() async {
    final outcome = await runCommand(
      ref.read(alexaRepositoryProvider),
      'wake_test',
      {'planId': widget.planId},
      timeout: const Duration(seconds: 90),
    );
    if (mounted) showError(context, outcome);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir despertar?'),
        content: const Text('O alarme reserva já agendado também será cancelado pela ponte.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(alexaRepositoryProvider).deleteWakePlan(widget.planId);
      if (mounted) context.go('/casa');
    } on RepositoryException {
      if (mounted) setState(() => _error = 'Não foi possível excluir.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final plansAsync = ref.watch(wakePlansProvider);
    final echos = (ref.watch(alexaDevicesProvider).value ?? const <AlexaDevice>[])
        .where((d) => d.kind == 'echo')
        .toList();
    return asyncView(plansAsync, (plans) {
      if (_draft == null) {
        if (!_isNew && !plans.any((p) => p.id == widget.planId)) {
          return Scaffold(appBar: AppBar(), body: const Center(child: EmptyHint('Despertar não encontrado.')));
        }
        _draft = _initial(plans, echos);
        _label.text = _draft!.label;
        _spotify.text = _draft!.spotifyQuery ?? '';
      }
      if (_draft!.echoDeviceId.isEmpty && echos.isNotEmpty) {
        _draft = _draft!.copyWith(echoDeviceId: echos.first.id); // dispositivos chegaram depois dos planos
      }
      final d = _draft!;
      final theme = Theme.of(context);
      return Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? 'Novo despertar' : 'Despertar'),
          actions: [
            if (!_isNew)
              IconButton(
                key: const Key('wake-delete'),
                tooltip: 'Excluir',
                icon: const Icon(Icons.delete_outline),
                onPressed: _delete,
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              key: const Key('wake-label'),
              controller: _label,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            ListTile(
              key: const Key('wake-time'),
              leading: const Icon(Icons.alarm),
              title: Text('${twoDigits(d.hour)}:${twoDigits(d.minute)}'),
              subtitle: const Text('Horário'),
              onTap: _pickTime,
            ),
            const SectionHeader('Dias'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 1; i <= 7; i++)
                  FilterChip(
                    key: ValueKey('day-$i'),
                    label: Text(weekdayShort[i - 1]),
                    selected: d.days.contains(i),
                    onSelected: (on) => _update((d) => d.copyWith(
                          days: on ? ([...d.days, i]..sort()) : d.days.where((x) => x != i).toList(),
                        )),
                  ),
              ],
            ),
            const SectionHeader('Echo'),
            if (echos.isEmpty)
              const EmptyHint('Nenhum Echo sincronizado. Toque em sincronizar na tela Casa.')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in echos)
                    ChoiceChip(
                      key: ValueKey('echo-${e.id}'),
                      label: Text(e.name),
                      selected: d.echoDeviceId == e.id,
                      onSelected: (_) => _update((d) => d.copyWith(echoDeviceId: e.id)),
                    ),
                ],
              ),
            const SectionHeader('Música'),
            TextField(
              key: const Key('wake-spotify'),
              controller: _spotify,
              decoration: const InputDecoration(
                labelText: 'Buscar no Spotify (opcional)',
                hintText: 'Ex.: playlist Bom Dia',
              ),
            ),
            SwitchListTile(
              title: const Text('Música antes do resumo'),
              value: d.musicFirst,
              onChanged: (v) => _update((d) => d.copyWith(musicFirst: v)),
            ),
            if (d.musicFirst)
              Wrap(
                spacing: 8,
                children: [
                  for (final m in const [1, 3, 5])
                    ChoiceChip(
                      label: Text('Resumo após $m min'),
                      selected: d.briefingDelayMin == m,
                      onSelected: (_) => _update((d) => d.copyWith(briefingDelayMin: m)),
                    ),
                ],
              ),
            ListTile(
              title: Text('Volume ${d.volume}%'),
              subtitle: Slider(
                value: d.volume.toDouble(),
                max: 100,
                divisions: 10,
                onChanged: (v) => _update((d) => d.copyWith(volume: v.round())),
              ),
            ),
            SwitchListTile(
              key: const Key('wake-fallback'),
              title: const Text('Alarme reserva'),
              subtitle: const Text('Se a ponte falhar, um alarme comum toca 10 minutos depois.'),
              value: d.fallbackAlarm,
              onChanged: (v) => _update((d) => d.copyWith(fallbackAlarm: v)),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, key: const Key('wake-error'), style: TextStyle(color: theme.colorScheme.error)),
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              children: [
                FilledButton(key: const Key('wake-save'), onPressed: _save, child: const Text('Salvar')),
                if (!_isNew)
                  OutlinedButton(key: const Key('wake-test'), onPressed: _test, child: const Text('Testar agora')),
              ],
            ),
          ],
        ),
      );
    });
  }
}
```

- [ ] **Step 6: Hoje com atalho e aviso, e main**

Replace all of `app/lib/features/today/today_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../domain/agenda.dart';
import '../../domain/alexa.dart';
import '../../domain/news.dart';
import '../../ui/common.dart';
import '../../ui/event_tile.dart';
import '../../ui/news_tile.dart';
import '../../ui/task_tile.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = ref.watch(clockProvider)();
    final events = ref.watch(eventsFromProvider(startOfDay(now)));
    final tasks = ref.watch(tasksProvider);
    final spaces = ref.watch(spacesProvider);
    final headlines = (ref.watch(newsFeedProvider).value ?? const <NewsItem>[]).take(3).toList();
    final warning = bridgeWarning(
      ref.watch(bridgeStatusProvider).value,
      ref.watch(wakePlansProvider).value ?? const <WakePlan>[],
      now,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(now)),
        actions: [
          IconButton(
            key: const Key('open-news'),
            tooltip: 'Notícias',
            icon: const Icon(Icons.newspaper_outlined),
            onPressed: () => context.go('/noticias'),
          ),
          IconButton(
            key: const Key('open-home'),
            tooltip: 'Casa',
            icon: const Icon(Icons.home_outlined),
            onPressed: () => context.go('/casa'),
          ),
        ],
      ),
      body: asyncView(events, (eventList) => asyncView(tasks, (taskList) {
            final names = {for (final s in spaces.value ?? const []) s.id: s.name};
            final agenda = buildDayAgenda(now: now, events: eventList, tasks: taskList);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (warning != null)
                  Card(
                    key: const Key('bridge-warning'),
                    color: theme.colorScheme.errorContainer,
                    child: ListTile(
                      leading: const Icon(Icons.warning_amber_outlined),
                      title: Text(warning),
                      onTap: () => context.go('/casa'),
                    ),
                  ),
                const SectionHeader('Aulas e eventos'),
                if (agenda.events.isEmpty) const EmptyHint('Nada na agenda hoje.'),
                for (final e in agenda.events) EventTile(event: e, spaceName: names[e.spaceId]),
                if (agenda.overdue.isNotEmpty) ...[
                  const SectionHeader('Atrasadas'),
                  for (final t in agenda.overdue)
                    TaskTile(key: ValueKey(t.id), task: t, spaceName: names[t.spaceId]),
                ],
                const SectionHeader('Para hoje'),
                if (agenda.dueToday.isEmpty) const EmptyHint('Nenhuma tarefa para hoje.'),
                for (final t in agenda.dueToday)
                  TaskTile(key: ValueKey(t.id), task: t, spaceName: names[t.spaceId]),
                if (headlines.isNotEmpty) ...[
                  const SectionHeader('Manchetes'),
                  for (final n in headlines) NewsTile(key: ValueKey('news-${n.id}'), item: n),
                ],
              ],
            );
          })),
    );
  }
}
```

Replace all of `app/lib/main.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'app/router.dart';
import 'data/supabase_alexa_repository.dart';
import 'data/supabase_news_repository.dart';
import 'data/supabase_repository.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  if (_supabaseUrl.isEmpty || _supabaseKey.isEmpty) {
    runApp(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Configure SUPABASE_URL e SUPABASE_ANON_KEY (veja app/env.example.json).'),
        ),
      ),
    ));
    return;
  }
  await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseKey);
  final client = Supabase.instance.client;
  final router = buildRouter(
    isSignedIn: () => client.auth.currentSession != null,
    refresh: StreamListenable(client.auth.onAuthStateChange),
  );
  runApp(ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(SupabaseRepository(client)),
      newsRepositoryProvider.overrideWithValue(SupabaseNewsRepository(client)),
      alexaRepositoryProvider.overrideWithValue(SupabaseAlexaRepository(client)),
    ],
    child: OrganizacionalApp(router: router),
  ));
}
```

- [ ] **Step 7: Rodar e ver passar (todas as fases)**

Run: `TZ=America/Sao_Paulo flutter test --exclude-tags integration && flutter analyze`
Expected: `All tests passed!`; sem erros nem warnings.

- [ ] **Step 8: Teste de ponta a ponta com a ponte no ar**

Com a Task 7 concluída, rode o app (`flutter run -d linux --dart-define-from-file=env.json`):
1. Casa → ⟳ (sincronizar): aparecem os Echos, as rotinas e os dispositivos; aparece "Feito.".
2. Toque em ▶ numa rotina: o Echo executa.
3. Crie um despertar para daqui a 5 minutos, com seu Echo e uma busca do Spotify; toque em **Testar agora**: toca a música e fala o resumo.
4. Espere o horário: o despertar toca sozinho. No SQL Editor, `select status, note from wake_runs order by created_at desc limit 1;` mostra `done`, e o alarme "(reserva)" some do app Alexa.
5. `docker compose stop bridge` na VPS; em até 3 minutos, Hoje mostra o aviso (se houver despertar ativo). Rode `docker compose start bridge`.

- [ ] **Step 9: Commit**

```bash
cd /home/only/organizacional
git add app
git commit -m "feat: tela Casa com despertares, rotinas, dispositivos e aviso da ponte em Hoje"
```
