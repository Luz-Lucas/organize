# Organizacional — Fase 1: Fundação — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Entregar um app Flutter (Linux/Windows + Android) com login, tela Hoje, Agenda semanal, Tarefas, Espaços (matérias/trabalhos/hobbies) e notas Markdown com `[[links]]` e backlinks, sincronizado pelo Supabase.

**Architecture:** O monorepo tem `supabase/` (migrations SQL + testes pgTAP) e `app/` (Flutter). O app separa `domain/` (modelos e regras puras, 100% testáveis), `data/` (interface `Repository` com implementação em memória para testes e implementação Supabase com streams realtime) e `features/` (telas com Riverpod + go_router). As colunas `source`/`external_id` já preparam os conectores das próximas fases.

**Tech Stack:** Flutter stable (Dart 3), flutter_riverpod 3, go_router, supabase_flutter 2, flutter_markdown_plus, intl (pt_BR), uuid; Supabase CLI via `npx supabase`, Postgres 15+, pgTAP.

**Spec:** `docs/superpowers/specs/2026-09-28-organizacional-design.md`

## Global Constraints

- Plataformas-alvo: Linux e Windows desktop + Android. Nada de iOS/macOS/web.
- Toda tabela tem `user_id uuid not null default auth.uid()` e RLS `user_id = auth.uid()` para select/insert/update/delete.
- Datas gravadas como `timestamptz` (UTC); o app converte para horário local ao ler (`toLocal()`) e para UTC ao gravar (`toUtc()`).
- Todo texto da UI é em pt-BR; datas formatadas com `intl` no locale `'pt_BR'`; a semana começa na segunda-feira.
- Identificadores de código em inglês; mensagens de commit no formato `tipo: descrição`.
- Título de nota único por usuário, sem diferenciar maiúsculas nem espaços extras (índice `lower(regexp_replace(btrim(title), '\s+', ' ', 'g'))`).
- Excluir um espaço apaga suas notas e tarefas (cascade) e mantém os eventos, que ficam com `space_id = null`.
- `source` (default `'manual'`) + `external_id` com índice único parcial em `tasks` e `events`, reservados para Google/GitHub.
- Chaves nunca vão para o git: `app/env.json` fica no `.gitignore`; `app/env.example.json` é versionado.
- Largura ≥ 720 px usa `NavigationRail`; abaixo disso, `NavigationBar` inferior.
- Testes rodam com `TZ=America/Sao_Paulo`.
- `flutter analyze` precisa terminar sem erros nem warnings; se aparecerem só `info` de estilo, rode `dart fix --apply` antes do commit.

## Review Focus

1. **Fuso horário:** um evento às 23:30 em Brasília (02:30Z do dia seguinte) tem que aparecer no dia local certo, e um evento que termina à meia-noite não pode aparecer no dia seguinte. Testes em `agenda_test.dart` (Task 3).
2. **Queda de rede ao salvar uma nota:** o texto digitado continua na tela, aparece um aviso persistente e o próximo salvamento bem-sucedido limpa o aviso. Testes em `note_screen_test.dart` (Task 6).
3. **Títulos de nota quase iguais** (`"Cálculo I"` vs `"  cálculo   i "`): o `[[link]]` resolve para a mesma nota, o banco rejeita a duplicata e a UI mostra "Já existe uma nota com esse título." Testes em `wikilinks_test.dart` (Task 3), `core_test.sql` (Task 1) e `note_screen_test.dart` (Task 6).
4. **Excluir um espaço com conteúdo:** a confirmação informa quantas notas e tarefas serão apagadas; os eventos continuam na agenda. Testes em `core_test.sql` (Task 1), `memory_repository_test.dart` (Task 4) e `spaces_test.dart` (Task 6).
5. **Tela de celular (400 px):** a navegação inferior aparece e funciona. Teste em `shell_test.dart` (Task 5).

---

## Mapa de arquivos

```
organizacional/
├── .gitignore
├── README.md                                   (Task 9)
├── supabase/
│   ├── config.toml                             (gerado, Task 1)
│   ├── migrations/20260928000000_core_schema.sql
│   └── tests/database/core_test.sql
└── app/                                        (flutter create, Task 2)
    ├── dart_test.yaml
    ├── env.example.json
    ├── android/app/src/main/AndroidManifest.xml (permissão INTERNET)
    ├── lib/
    │   ├── main.dart                           bootstrap Supabase + ProviderScope
    │   ├── app/app.dart                        OrganizacionalApp (MaterialApp.router, locale)
    │   ├── app/theme.dart                      buildTheme()
    │   ├── app/router.dart                     buildRouter(), StreamListenable
    │   ├── app/shell.dart                      AppShell (rail/bar responsivo)
    │   ├── app/providers.dart                  repositoryProvider, clockProvider, streams
    │   ├── domain/json.dart                    parseDate/encodeDate
    │   ├── domain/ids.dart                     newId()
    │   ├── domain/space.dart                   Space, SpaceKind
    │   ├── domain/note.dart                    Note
    │   ├── domain/task_item.dart               TaskItem, TaskStatus
    │   ├── domain/calendar_event.dart          CalendarEvent
    │   ├── domain/wikilinks.dart               parse/resolve/backlinks/uniqueTitle
    │   ├── domain/agenda.dart                  startOfWeek, eventsOnDay, groupTasks, buildDayAgenda
    │   ├── data/repository.dart                Repository, RepositoryException
    │   ├── data/memory_repository.dart         MemoryRepository (testes)
    │   ├── data/supabase_repository.dart       SupabaseRepository
    │   ├── ui/common.dart                      asyncView, SectionHeader, EmptyHint, plural, showError
    │   ├── ui/task_tile.dart                   TaskTile
    │   ├── ui/event_tile.dart                  EventTile
    │   └── features/
    │       ├── auth/login_screen.dart
    │       ├── today/today_screen.dart
    │       ├── agenda/agenda_screen.dart
    │       ├── agenda/event_dialog.dart
    │       ├── tasks/tasks_screen.dart
    │       ├── spaces/spaces_screen.dart       (+ SpaceDialog)
    │       ├── spaces/space_screen.dart
    │       └── notes/note_screen.dart
    └── test/
        ├── flutter_test_config.dart
        ├── helpers.dart
        ├── domain/{models,wikilinks,agenda}_test.dart
        ├── data/{memory_repository,supabase_repository}_test.dart
        ├── app/shell_test.dart
        ├── ui/task_tile_test.dart
        └── features/{spaces,notes,tasks,today,agenda}_test.dart
```

**Paralelização:** Task 1 ∥ (Task 2 → Task 3). A Task 4 depende de 1 e 3. A Task 5 depende de 4. As Tasks 6, 7 e 8 mexem em arquivos disjuntos e rodam em paralelo depois da 5. A Task 9 fecha.

---

### Task 1: Repositório git, schema Supabase e RLS

**Files:**
- Create: `.gitignore`
- Create: `supabase/config.toml` (via `supabase init`)
- Create: `supabase/migrations/20260928000000_core_schema.sql`
- Test: `supabase/tests/database/core_test.sql`

**Interfaces:**
- Consumes: nada.
- Produces: tabelas `public.spaces(id, user_id, name, kind, icon, color, position, created_at, updated_at)`, `public.notes(id, user_id, space_id, parent_id, title, body, created_at, updated_at)`, `public.tasks(id, user_id, space_id, note_id, title, description, status, due_at, completed_at, source, external_id, created_at, updated_at)`, `public.events(id, user_id, space_id, title, starts_at, ends_at, all_day, location, source, external_id, created_at, updated_at)`; enums `space_kind('materia','trabalho','hobby','geral')` e `task_status('todo','doing','done')`; todas na publicação `supabase_realtime`.

- [x] **Step 1: Conferir ferramentas e iniciar o repositório**

Run:
```bash
cd /home/only/organizacional
node -v && docker info --format '{{.ServerVersion}}'
git init
cat > .gitignore <<'EOF'
app/env.json
.env
supabase/.temp/
supabase/.branches/
EOF
npx supabase@latest init
```
Expected: versões do Node e do Docker impressas; `Finished supabase init.` Se o Docker não estiver rodando, instale/inicie antes (`sudo systemctl start docker`); o Supabase local depende dele.

- [x] **Step 2: Escrever o teste pgTAP (falha, porque as tabelas não existem)**

Create `supabase/tests/database/core_test.sql`:
```sql
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.dev');

-- Usuário A
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);

select lives_ok(
  $$ insert into spaces (id, name, kind) values ('aaaaaaaa-0000-0000-0000-000000000001', 'Cálculo I', 'materia') $$,
  'A cria um espaço');
select is(
  (select user_id from spaces where id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  '11111111-1111-1111-1111-111111111111'::uuid,
  'user_id vem de auth.uid()');
select lives_ok(
  $$ insert into notes (id, space_id, title) values ('aaaaaaaa-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', 'Limites') $$,
  'A cria uma nota');
select throws_ok(
  $$ insert into notes (space_id, title) values ('aaaaaaaa-0000-0000-0000-000000000001', '  limites ') $$,
  '23505', null,
  'título duplicado (ignorando caixa e espaços) é rejeitado');

insert into tasks (space_id, title) values ('aaaaaaaa-0000-0000-0000-000000000001', 'Lista 1');
insert into events (space_id, title, starts_at, ends_at)
  values ('aaaaaaaa-0000-0000-0000-000000000001', 'Aula', now(), now() + interval '1 hour');

-- Usuário B
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
select is((select count(*) from spaces)::int, 0, 'B não vê os espaços de A');
select throws_ok(
  $$ insert into spaces (user_id, name) values ('11111111-1111-1111-1111-111111111111', 'invasão') $$,
  '42501', null,
  'B não cria linhas em nome de A');

-- De volta a A: excluir o espaço
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
delete from spaces where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select is(
  (select count(*) from notes)::int + (select count(*) from tasks)::int, 0,
  'notas e tarefas somem junto com o espaço');
select is(
  (select count(*) from events where space_id is null)::int, 1,
  'o evento continua na agenda, sem espaço');

select * from finish();
rollback;
```

- [x] **Step 3: Rodar e ver falhar**

Run: `npx supabase start && npx supabase test db`
Expected: FAIL com `relation "spaces" does not exist`.

- [x] **Step 4: Escrever a migration**

Create `supabase/migrations/20260928000000_core_schema.sql`:
```sql
create type public.space_kind as enum ('materia', 'trabalho', 'hobby', 'geral');
create type public.task_status as enum ('todo', 'doing', 'done');

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.spaces (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null check (length(btrim(name)) > 0),
  kind public.space_kind not null default 'geral',
  icon text,
  color text,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  space_id uuid references public.spaces (id) on delete cascade,
  parent_id uuid references public.notes (id) on delete cascade,
  title text not null check (length(btrim(title)) > 0),
  body text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index notes_user_title_uq
  on public.notes (user_id, lower(regexp_replace(btrim(title), '\s+', ' ', 'g')));
create index notes_space_idx on public.notes (space_id);

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  space_id uuid references public.spaces (id) on delete cascade,
  note_id uuid references public.notes (id) on delete set null,
  title text not null check (length(btrim(title)) > 0),
  description text not null default '',
  status public.task_status not null default 'todo',
  due_at timestamptz,
  completed_at timestamptz,
  source text not null default 'manual',
  external_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index tasks_external_uq on public.tasks (user_id, source, external_id) where external_id is not null;
create index tasks_due_idx on public.tasks (user_id, due_at);

create table public.events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  space_id uuid references public.spaces (id) on delete set null,
  title text not null check (length(btrim(title)) > 0),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  all_day boolean not null default false,
  location text,
  source text not null default 'manual',
  external_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at >= starts_at)
);
create unique index events_external_uq on public.events (user_id, source, external_id) where external_id is not null;
create index events_range_idx on public.events (user_id, starts_at, ends_at);

do $$
declare t text;
begin
  foreach t in array array['spaces', 'notes', 'tasks', 'events'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy "dono" on public.%I for all to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))',
      t);
    execute format(
      'create trigger touch_updated_at before update on public.%I for each row execute function public.touch_updated_at()',
      t);
  end loop;
end $$;

alter publication supabase_realtime add table public.spaces, public.notes, public.tasks, public.events;
```

- [x] **Step 5: Aplicar e rodar os testes**

Run: `npx supabase db reset && npx supabase test db`
Expected: PASS, `All tests successful. Files=1, Tests=8`.

- [x] **Step 6: Commit**

```bash
git add .gitignore supabase docs
git commit -m "feat: schema do núcleo (espaços, notas, tarefas, eventos) com RLS"
```

---

### Task 2: Projeto Flutter e modelos de domínio

**Files:**
- Create: `app/` (via `flutter create`)
- Create: `app/dart_test.yaml`, `app/test/flutter_test_config.dart`
- Create: `app/lib/domain/json.dart`, `ids.dart`, `space.dart`, `note.dart`, `task_item.dart`, `calendar_event.dart`
- Delete: `app/test/widget_test.dart`
- Test: `app/test/domain/models_test.dart`

**Interfaces:**
- Consumes: nomes de colunas da Task 1.
- Produces:
  - `DateTime? parseDate(Object? value)`, `String? encodeDate(DateTime? value)`
  - `String newId()`
  - `enum SpaceKind { materia, trabalho, hobby, geral }` com `String singular`, `String plural`
  - `class Space({required String id, required String name, SpaceKind kind = SpaceKind.geral, int position = 0})` + `fromMap`, `toMap`, `copyWith({String? name, SpaceKind? kind, int? position})`, `==`
  - `class Note({required String id, required String title, String body = '', String? spaceId, String? parentId, DateTime? updatedAt})` + `fromMap`, `toMap`, `copyWith({String? title, String? body})`, `==`
  - `enum TaskStatus { todo, doing, done }`; `class TaskItem({required String id, required String title, String description = '', TaskStatus status = TaskStatus.todo, DateTime? dueAt, DateTime? completedAt, String? spaceId, String? noteId, String source = 'manual', String? externalId})` + `bool isDone`, `TaskItem toggled(DateTime now)`, `fromMap`, `toMap`, `==`
  - `class CalendarEvent({required String id, required String title, required DateTime startsAt, required DateTime endsAt, bool allDay = false, String? location, String? spaceId, String source = 'manual', String? externalId})` + `CalendarEvent withoutSpace()`, `fromMap`, `toMap`, `==`

- [x] **Step 1: Instalar o Flutter (se `flutter --version` falhar)**

Run:
```bash
sudo snap install flutter --classic
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev
flutter config --enable-linux-desktop
flutter doctor
```
Expected: `flutter doctor` com ✓ em Flutter e Linux toolchain. Para Android, instale o Android Studio (SDK + cmdline-tools) e rode `flutter doctor --android-licenses`. O Android só é necessário na Task 9.

- [x] **Step 2: Criar o projeto e as dependências**

Run:
```bash
cd /home/only/organizacional
flutter create --org dev.organizacional --project-name organizacional --platforms=linux,windows,android app
cd app
rm test/widget_test.dart
flutter pub add flutter_localizations --sdk=flutter
flutter pub add flutter_riverpod go_router supabase_flutter flutter_markdown_plus intl uuid
```
Expected: `Got dependencies!` sem conflitos.

Create `app/dart_test.yaml`:
```yaml
tags:
  integration: {}
```

Create `app/test/flutter_test_config.dart`:
```dart
import 'dart:async';

import 'package:intl/date_symbol_data_local.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await initializeDateFormatting('pt_BR');
  await testMain();
}
```

- [x] **Step 3: Escrever o teste dos modelos**

Create `app/test/domain/models_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/ids.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/space.dart';
import 'package:organizacional/domain/task_item.dart';

void main() {
  test('newId gera uuids diferentes', () {
    expect(newId(), isNot(newId()));
    expect(newId(), hasLength(36));
  });

  test('Space ida e volta pelo mapa', () {
    const s = Space(id: 's1', name: 'Cálculo I', kind: SpaceKind.materia, position: 2);
    expect(Space.fromMap(s.toMap()), s);
    expect(s.toMap()['kind'], 'materia');
  });

  test('Note ida e volta pelo mapa', () {
    const n = Note(id: 'n1', title: 'Limites', body: '# Limites', spaceId: 's1');
    expect(Note.fromMap(n.toMap()), n);
  });

  test('TaskItem ida e volta com datas locais', () {
    final t = TaskItem(
      id: 't1',
      title: 'Lista 1',
      status: TaskStatus.doing,
      dueAt: DateTime(2026, 9, 28, 23, 59),
      spaceId: 's1',
    );
    expect(TaskItem.fromMap(t.toMap()), t);
  });

  test('datas vão para o banco em UTC', () {
    final t = TaskItem(id: 't1', title: 'x', dueAt: DateTime.utc(2026, 9, 28, 12));
    expect(t.toMap()['due_at'], '2026-09-28T12:00:00.000Z');
  });

  test('toggled marca e desmarca conclusão', () {
    final now = DateTime(2026, 9, 28, 10);
    const t = TaskItem(id: 't1', title: 'x');
    final done = t.toggled(now);
    expect(done.isDone, isTrue);
    expect(done.completedAt, now);
    final undone = done.toggled(now);
    expect(undone.status, TaskStatus.todo);
    expect(undone.completedAt, isNull);
  });

  test('CalendarEvent ida e volta e withoutSpace', () {
    final e = CalendarEvent(
      id: 'e1',
      title: 'Aula',
      startsAt: DateTime(2026, 9, 28, 8),
      endsAt: DateTime(2026, 9, 28, 9, 40),
      location: 'Sala 12',
      spaceId: 's1',
    );
    expect(CalendarEvent.fromMap(e.toMap()), e);
    expect(e.withoutSpace().spaceId, isNull);
    expect(e.withoutSpace().title, 'Aula');
  });

  test('fromMap aceita timestamp do Postgres com offset e converte para local', () {
    final e = CalendarEvent.fromMap({
      'id': 'e1',
      'title': 'Aula',
      'starts_at': '2026-09-28T11:00:00+00:00',
      'ends_at': '2026-09-28T12:40:00+00:00',
      'all_day': false,
      'location': null,
      'space_id': null,
      'source': 'google',
      'external_id': 'abc',
    });
    expect(e.startsAt.toUtc(), DateTime.utc(2026, 9, 28, 11));
    expect(e.startsAt.isUtc, isFalse);
    expect(e.source, 'google');
    expect(e.externalId, 'abc');
  });
}
```

- [x] **Step 4: Rodar e ver falhar**

Run: `cd app && TZ=America/Sao_Paulo flutter test test/domain/models_test.dart`
Expected: FAIL com `Error: Couldn't resolve the package 'organizacional/domain/...'` / `Undefined name`.

- [x] **Step 5: Implementar os modelos**

Create `app/lib/domain/json.dart`:
```dart
DateTime? parseDate(Object? value) =>
    value == null ? null : DateTime.parse(value as String).toLocal();

String? encodeDate(DateTime? value) => value?.toUtc().toIso8601String();
```

Create `app/lib/domain/ids.dart`:
```dart
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

String newId() => _uuid.v4();
```

Create `app/lib/domain/space.dart`:
```dart
enum SpaceKind {
  materia('Matéria', 'Matérias'),
  trabalho('Trabalho', 'Trabalhos'),
  hobby('Hobby', 'Hobbies'),
  geral('Geral', 'Geral');

  const SpaceKind(this.singular, this.plural);

  final String singular;
  final String plural;
}

class Space {
  const Space({
    required this.id,
    required this.name,
    this.kind = SpaceKind.geral,
    this.position = 0,
  });

  final String id;
  final String name;
  final SpaceKind kind;
  final int position;

  factory Space.fromMap(Map<String, dynamic> m) => Space(
        id: m['id'] as String,
        name: m['name'] as String,
        kind: SpaceKind.values.byName(m['kind'] as String),
        position: (m['position'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'position': position,
      };

  Space copyWith({String? name, SpaceKind? kind, int? position}) => Space(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        position: position ?? this.position,
      );

  @override
  bool operator ==(Object other) =>
      other is Space &&
      other.id == id &&
      other.name == name &&
      other.kind == kind &&
      other.position == position;

  @override
  int get hashCode => Object.hash(id, name, kind, position);
}
```

Create `app/lib/domain/note.dart`:
```dart
import 'json.dart';

class Note {
  const Note({
    required this.id,
    required this.title,
    this.body = '',
    this.spaceId,
    this.parentId,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String body;
  final String? spaceId;
  final String? parentId;
  final DateTime? updatedAt;

  factory Note.fromMap(Map<String, dynamic> m) => Note(
        id: m['id'] as String,
        title: m['title'] as String,
        body: (m['body'] as String?) ?? '',
        spaceId: m['space_id'] as String?,
        parentId: m['parent_id'] as String?,
        updatedAt: parseDate(m['updated_at']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'body': body,
        'space_id': spaceId,
        'parent_id': parentId,
      };

  Note copyWith({String? title, String? body}) => Note(
        id: id,
        title: title ?? this.title,
        body: body ?? this.body,
        spaceId: spaceId,
        parentId: parentId,
        updatedAt: updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is Note &&
      other.id == id &&
      other.title == title &&
      other.body == body &&
      other.spaceId == spaceId &&
      other.parentId == parentId;

  @override
  int get hashCode => Object.hash(id, title, body, spaceId, parentId);
}
```

Create `app/lib/domain/task_item.dart`:
```dart
import 'json.dart';

enum TaskStatus { todo, doing, done }

class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    this.description = '',
    this.status = TaskStatus.todo,
    this.dueAt,
    this.completedAt,
    this.spaceId,
    this.noteId,
    this.source = 'manual',
    this.externalId,
  });

  final String id;
  final String title;
  final String description;
  final TaskStatus status;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final String? spaceId;
  final String? noteId;
  final String source;
  final String? externalId;

  bool get isDone => status == TaskStatus.done;

  TaskItem toggled(DateTime now) => TaskItem(
        id: id,
        title: title,
        description: description,
        status: isDone ? TaskStatus.todo : TaskStatus.done,
        dueAt: dueAt,
        completedAt: isDone ? null : now,
        spaceId: spaceId,
        noteId: noteId,
        source: source,
        externalId: externalId,
      );

  factory TaskItem.fromMap(Map<String, dynamic> m) => TaskItem(
        id: m['id'] as String,
        title: m['title'] as String,
        description: (m['description'] as String?) ?? '',
        status: TaskStatus.values.byName(m['status'] as String),
        dueAt: parseDate(m['due_at']),
        completedAt: parseDate(m['completed_at']),
        spaceId: m['space_id'] as String?,
        noteId: m['note_id'] as String?,
        source: (m['source'] as String?) ?? 'manual',
        externalId: m['external_id'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'description': description,
        'status': status.name,
        'due_at': encodeDate(dueAt),
        'completed_at': encodeDate(completedAt),
        'space_id': spaceId,
        'note_id': noteId,
        'source': source,
        'external_id': externalId,
      };

  @override
  bool operator ==(Object other) =>
      other is TaskItem &&
      other.id == id &&
      other.title == title &&
      other.description == description &&
      other.status == status &&
      other.dueAt == dueAt &&
      other.completedAt == completedAt &&
      other.spaceId == spaceId &&
      other.noteId == noteId &&
      other.source == source &&
      other.externalId == externalId;

  @override
  int get hashCode => Object.hash(id, title, description, status, dueAt,
      completedAt, spaceId, noteId, source, externalId);
}
```

Create `app/lib/domain/calendar_event.dart`:
```dart
import 'json.dart';

class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    this.allDay = false,
    this.location,
    this.spaceId,
    this.source = 'manual',
    this.externalId,
  });

  final String id;
  final String title;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool allDay;
  final String? location;
  final String? spaceId;
  final String source;
  final String? externalId;

  CalendarEvent withoutSpace() => CalendarEvent(
        id: id,
        title: title,
        startsAt: startsAt,
        endsAt: endsAt,
        allDay: allDay,
        location: location,
        source: source,
        externalId: externalId,
      );

  factory CalendarEvent.fromMap(Map<String, dynamic> m) => CalendarEvent(
        id: m['id'] as String,
        title: m['title'] as String,
        startsAt: parseDate(m['starts_at'])!,
        endsAt: parseDate(m['ends_at'])!,
        allDay: (m['all_day'] as bool?) ?? false,
        location: m['location'] as String?,
        spaceId: m['space_id'] as String?,
        source: (m['source'] as String?) ?? 'manual',
        externalId: m['external_id'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'starts_at': encodeDate(startsAt),
        'ends_at': encodeDate(endsAt),
        'all_day': allDay,
        'location': location,
        'space_id': spaceId,
        'source': source,
        'external_id': externalId,
      };

  @override
  bool operator ==(Object other) =>
      other is CalendarEvent &&
      other.id == id &&
      other.title == title &&
      other.startsAt == startsAt &&
      other.endsAt == endsAt &&
      other.allDay == allDay &&
      other.location == location &&
      other.spaceId == spaceId &&
      other.source == source &&
      other.externalId == externalId;

  @override
  int get hashCode => Object.hash(id, title, startsAt, endsAt, allDay,
      location, spaceId, source, externalId);
}
```

- [x] **Step 6: Rodar e ver passar**

Run: `TZ=America/Sao_Paulo flutter test test/domain/models_test.dart && flutter analyze`
Expected: `All tests passed!` e `No issues found!`. O `main.dart` gerado pelo template ainda compila; ele é substituído na Task 5.

- [x] **Step 7: Commit**

```bash
cd /home/only/organizacional
git add app
git commit -m "feat: projeto Flutter e modelos de domínio"
```

---

### Task 3: Regras de domínio — wikilinks e agenda

**Files:**
- Create: `app/lib/domain/wikilinks.dart`, `app/lib/domain/agenda.dart`
- Test: `app/test/domain/wikilinks_test.dart`, `app/test/domain/agenda_test.dart`

**Interfaces:**
- Consumes: `Note`, `TaskItem`, `TaskStatus`, `CalendarEvent` (Task 2).
- Produces:
  - `class WikiLink { final String target; final String label; }`
  - `String normalizeTitle(String title)`, `List<WikiLink> parseWikiLinks(String body)`, `Note? resolveWikiLink(String target, Iterable<Note> notes)`, `List<Note> backlinksFor(Note target, Iterable<Note> notes)`, `String wikiLinksToMarkdown(String body)` (gera `[label](wiki:<target codificado>)`), `String uniqueTitle(String base, Iterable<Note> notes)`
  - `DateTime startOfDay(DateTime d)`, `DateTime startOfWeek(DateTime d)`, `List<CalendarEvent> eventsOnDay(Iterable<CalendarEvent> events, DateTime day)`
  - `enum TaskGroup { atrasadas, hoje, proximas, semData, concluidas }` com `String label` (`'Atrasadas'`, `'Para hoje'`, `'Próximas'`, `'Sem data'`, `'Concluídas'`)
  - `Map<TaskGroup, List<TaskItem>> groupTasks(Iterable<TaskItem> tasks, DateTime now)`
  - `class DayAgenda { List<CalendarEvent> events; List<TaskItem> overdue; List<TaskItem> dueToday; }`, `DayAgenda buildDayAgenda({required DateTime now, required Iterable<CalendarEvent> events, required Iterable<TaskItem> tasks})`
  - `String? validateEventTimes(DateTime start, DateTime end)`

- [x] **Step 1: Escrever os testes**

Create `app/test/domain/wikilinks_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/wikilinks.dart';

void main() {
  test('parse encontra links simples e com apelido', () {
    final links = parseWikiLinks('Ver [[Cálculo I]] e [[Álgebra Linear|álgebra]].');
    expect(links.map((l) => l.target), ['Cálculo I', 'Álgebra Linear']);
    expect(links.map((l) => l.label), ['Cálculo I', 'álgebra']);
  });

  test('ignora colchetes vazios', () {
    expect(parseWikiLinks('[[ ]] e [[]]'), isEmpty);
  });

  test('resolve ignorando caixa e espaços extras', () {
    const notes = [Note(id: 'n1', title: 'Cálculo I')];
    expect(resolveWikiLink('  cálculo   i ', notes)?.id, 'n1');
  });

  test('link sem nota correspondente resolve para null', () {
    const notes = [Note(id: 'n1', title: 'Cálculo I')];
    expect(resolveWikiLink('Física', notes), isNull);
  });

  test('backlinks lista quem menciona a nota, sem ela mesma', () {
    const target = Note(id: 'n1', title: 'Limites', body: 'ver [[Limites]]');
    const notes = [
      target,
      Note(id: 'n2', title: 'Derivadas', body: 'usa [[limites]]'),
      Note(id: 'n3', title: 'Física', body: 'nada aqui'),
    ];
    expect(backlinksFor(target, notes).map((n) => n.id), ['n2']);
  });

  test('wikiLinksToMarkdown gera link wiki: codificado', () {
    expect(wikiLinksToMarkdown('[[Cálculo I|calc]] e [[Física]]'),
        '[calc](wiki:C%C3%A1lculo%20I) e [Física](wiki:F%C3%ADsica)');
  });

  test('uniqueTitle numera títulos repetidos', () {
    const notes = [Note(id: 'a', title: 'Sem título'), Note(id: 'b', title: 'sem título 2')];
    expect(uniqueTitle('Sem título', notes), 'Sem título 3');
    expect(uniqueTitle('Nova', notes), 'Nova');
  });
}
```

Create `app/test/domain/agenda_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/agenda.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/task_item.dart';

void main() {
  final now = DateTime(2026, 9, 28, 10); // segunda-feira

  TaskItem task(String id, {DateTime? due, bool done = false}) => TaskItem(
        id: id,
        title: id,
        dueAt: due,
        status: done ? TaskStatus.done : TaskStatus.todo,
        completedAt: done ? now : null,
      );

  CalendarEvent event(String id, DateTime start, DateTime end) =>
      CalendarEvent(id: id, title: id, startsAt: start, endsAt: end);

  test('a semana começa na segunda', () {
    expect(startOfWeek(DateTime(2026, 10, 1, 15)), DateTime(2026, 9, 28));
    expect(startOfWeek(DateTime(2026, 10, 4)), DateTime(2026, 9, 28));
    expect(startOfWeek(DateTime(2026, 9, 28)), DateTime(2026, 9, 28));
  });

  group('eventsOnDay', () {
    test('inclui só os eventos do dia, ordenados pelo início', () {
      final b = event('b', DateTime(2026, 9, 28, 14), DateTime(2026, 9, 28, 15));
      final a = event('a', DateTime(2026, 9, 28, 8), DateTime(2026, 9, 28, 9));
      final other = event('x', DateTime(2026, 9, 29, 8), DateTime(2026, 9, 29, 9));
      expect(eventsOnDay([b, other, a], DateTime(2026, 9, 28)), [a, b]);
    });

    test('evento que termina à meia-noite não vaza para o dia seguinte', () {
      final e = event('noite', DateTime(2026, 9, 27, 22), DateTime(2026, 9, 28));
      expect(eventsOnDay([e], DateTime(2026, 9, 28)), isEmpty);
      expect(eventsOnDay([e], DateTime(2026, 9, 27)), [e]);
    });

    test('evento que atravessa a meia-noite aparece nos dois dias', () {
      final e = event('festa', DateTime(2026, 9, 27, 23), DateTime(2026, 9, 28, 1));
      expect(eventsOnDay([e], DateTime(2026, 9, 27)), [e]);
      expect(eventsOnDay([e], DateTime(2026, 9, 28)), [e]);
    });

    test('evento de duração zero à meia-noite pertence ao dia que começa', () {
      final e = event('marco', DateTime(2026, 9, 28), DateTime(2026, 9, 28));
      expect(eventsOnDay([e], DateTime(2026, 9, 28)), [e]);
      expect(eventsOnDay([e], DateTime(2026, 9, 27)), isEmpty);
    });

    final brasilia = DateTime(2026, 9, 27).timeZoneOffset == const Duration(hours: -3);
    test('evento às 23:30 de Brasília (02:30Z) fica no dia local', () {
      final e = CalendarEvent.fromMap({
        'id': 'e1',
        'title': 'Aula noturna',
        'starts_at': '2026-09-28T02:30:00+00:00',
        'ends_at': '2026-09-28T02:50:00+00:00',
      });
      expect(eventsOnDay([e], DateTime(2026, 9, 27)), [e]);
      expect(eventsOnDay([e], DateTime(2026, 9, 28)), isEmpty);
    }, skip: brasilia ? false : 'rode com TZ=America/Sao_Paulo');
  });

  group('groupTasks', () {
    test('separa atrasadas, hoje, próximas, sem data e concluídas', () {
      final groups = groupTasks([
        task('amanha', due: DateTime(2026, 9, 29, 23, 59)),
        task('ontem', due: DateTime(2026, 9, 27, 23, 59)),
        task('hoje', due: DateTime(2026, 9, 28, 23, 59)),
        task('livre'),
        task('feita', due: DateTime(2026, 9, 20), done: true),
      ], now);
      expect(groups[TaskGroup.atrasadas]!.map((t) => t.id), ['ontem']);
      expect(groups[TaskGroup.hoje]!.map((t) => t.id), ['hoje']);
      expect(groups[TaskGroup.proximas]!.map((t) => t.id), ['amanha']);
      expect(groups[TaskGroup.semData]!.map((t) => t.id), ['livre']);
      expect(groups[TaskGroup.concluidas]!.map((t) => t.id), ['feita']);
    });

    test('prazo às 00:00 de hoje conta como hoje, não como atrasada', () {
      final groups = groupTasks([task('meianoite', due: DateTime(2026, 9, 28))], now);
      expect(groups[TaskGroup.hoje]!.single.id, 'meianoite');
    });
  });

  test('buildDayAgenda junta os eventos do dia e as tarefas pendentes', () {
    final aula = event('aula', DateTime(2026, 9, 28, 8), DateTime(2026, 9, 28, 9, 40));
    final agenda = buildDayAgenda(
      now: now,
      events: [aula, event('amanha', DateTime(2026, 9, 29, 8), DateTime(2026, 9, 29, 9))],
      tasks: [
        task('ontem', due: DateTime(2026, 9, 27)),
        task('hoje', due: DateTime(2026, 9, 28, 18)),
        task('feita', due: DateTime(2026, 9, 28, 18), done: true),
      ],
    );
    expect(agenda.events, [aula]);
    expect(agenda.overdue.map((t) => t.id), ['ontem']);
    expect(agenda.dueToday.map((t) => t.id), ['hoje']);
  });

  test('validateEventTimes exige fim depois do início', () {
    final start = DateTime(2026, 9, 28, 10);
    expect(validateEventTimes(start, start.add(const Duration(hours: 1))), isNull);
    expect(validateEventTimes(start, start), 'O fim precisa ser depois do início.');
  });
}
```

- [x] **Step 2: Rodar e ver falhar**

Run: `cd app && TZ=America/Sao_Paulo flutter test test/domain`
Expected: FAIL (`wikilinks.dart` e `agenda.dart` não existem).

- [x] **Step 3: Implementar**

Create `app/lib/domain/wikilinks.dart`:
```dart
import 'note.dart';

class WikiLink {
  const WikiLink(this.target, this.label);

  final String target;
  final String label;
}

final _wikiLink = RegExp(r'\[\[([^\[\]|]+?)(?:\|([^\[\]]+?))?\]\]');
final _spaces = RegExp(r'\s+');

String normalizeTitle(String title) =>
    title.trim().replaceAll(_spaces, ' ').toLowerCase();

List<WikiLink> parseWikiLinks(String body) => [
      for (final m in _wikiLink.allMatches(body))
        if (m.group(1)!.trim().isNotEmpty)
          WikiLink(m.group(1)!.trim(), (m.group(2) ?? m.group(1)!).trim()),
    ];

Note? resolveWikiLink(String target, Iterable<Note> notes) {
  final key = normalizeTitle(target);
  for (final note in notes) {
    if (normalizeTitle(note.title) == key) return note;
  }
  return null;
}

List<Note> backlinksFor(Note target, Iterable<Note> notes) {
  final key = normalizeTitle(target.title);
  return notes
      .where((n) =>
          n.id != target.id &&
          parseWikiLinks(n.body).any((l) => normalizeTitle(l.target) == key))
      .toList()
    ..sort((a, b) => a.title.compareTo(b.title));
}

String wikiLinksToMarkdown(String body) => body.replaceAllMapped(_wikiLink, (m) {
      final target = m.group(1)!.trim();
      if (target.isEmpty) return m.group(0)!;
      final label = (m.group(2) ?? m.group(1)!).trim();
      return '[$label](wiki:${Uri.encodeComponent(target)})';
    });

String uniqueTitle(String base, Iterable<Note> notes) {
  final taken = {for (final n in notes) normalizeTitle(n.title)};
  if (!taken.contains(normalizeTitle(base))) return base;
  var i = 2;
  while (taken.contains(normalizeTitle('$base $i'))) {
    i++;
  }
  return '$base $i';
}
```

Create `app/lib/domain/agenda.dart`:
```dart
import 'calendar_event.dart';
import 'task_item.dart';

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime startOfWeek(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - DateTime.monday));

List<CalendarEvent> eventsOnDay(Iterable<CalendarEvent> events, DateTime day) {
  final start = DateTime(day.year, day.month, day.day);
  final end = DateTime(day.year, day.month, day.day + 1);
  bool overlaps(CalendarEvent e) =>
      e.startsAt.isBefore(end) &&
      (e.endsAt.isAfter(start) || !e.startsAt.isBefore(start));
  return events.where(overlaps).toList()
    ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
}

enum TaskGroup {
  atrasadas('Atrasadas'),
  hoje('Para hoje'),
  proximas('Próximas'),
  semData('Sem data'),
  concluidas('Concluídas');

  const TaskGroup(this.label);

  final String label;
}

Map<TaskGroup, List<TaskItem>> groupTasks(Iterable<TaskItem> tasks, DateTime now) {
  final start = DateTime(now.year, now.month, now.day);
  final end = DateTime(now.year, now.month, now.day + 1);
  final out = {for (final g in TaskGroup.values) g: <TaskItem>[]};
  for (final t in tasks) {
    final due = t.dueAt;
    final group = t.isDone
        ? TaskGroup.concluidas
        : due == null
            ? TaskGroup.semData
            : due.isBefore(start)
                ? TaskGroup.atrasadas
                : due.isBefore(end)
                    ? TaskGroup.hoje
                    : TaskGroup.proximas;
    out[group]!.add(t);
  }
  int byDue(TaskItem a, TaskItem b) => a.dueAt!.compareTo(b.dueAt!);
  out[TaskGroup.atrasadas]!.sort(byDue);
  out[TaskGroup.hoje]!.sort(byDue);
  out[TaskGroup.proximas]!.sort(byDue);
  out[TaskGroup.semData]!.sort((a, b) => a.title.compareTo(b.title));
  final epoch = DateTime(0);
  out[TaskGroup.concluidas]!
      .sort((a, b) => (b.completedAt ?? epoch).compareTo(a.completedAt ?? epoch));
  return out;
}

class DayAgenda {
  const DayAgenda({required this.events, required this.overdue, required this.dueToday});

  final List<CalendarEvent> events;
  final List<TaskItem> overdue;
  final List<TaskItem> dueToday;
}

DayAgenda buildDayAgenda({
  required DateTime now,
  required Iterable<CalendarEvent> events,
  required Iterable<TaskItem> tasks,
}) {
  final groups = groupTasks(tasks, now);
  return DayAgenda(
    events: eventsOnDay(events, now),
    overdue: groups[TaskGroup.atrasadas]!,
    dueToday: groups[TaskGroup.hoje]!,
  );
}

String? validateEventTimes(DateTime start, DateTime end) =>
    end.isAfter(start) ? null : 'O fim precisa ser depois do início.';
```

- [x] **Step 4: Rodar e ver passar (nenhum teste pode aparecer como skipped)**

Run: `TZ=America/Sao_Paulo flutter test test/domain && flutter analyze`
Expected: `All tests passed!` sem `skipped`; `No issues found!`

- [x] **Step 5: Commit**

```bash
cd /home/only/organizacional
git add app/lib/domain app/test/domain
git commit -m "feat: wikilinks, backlinks e regras de agenda"
```

---

### Task 4: Camada de dados — Repository, memória e Supabase

**Files:**
- Create: `app/lib/data/repository.dart`, `app/lib/data/memory_repository.dart`, `app/lib/data/supabase_repository.dart`
- Test: `app/test/data/memory_repository_test.dart`, `app/test/data/supabase_repository_test.dart` (tag `integration`)

**Interfaces:**
- Consumes: modelos da Task 2; `normalizeTitle` da Task 3; schema da Task 1.
- Produces:
  - `class RepositoryException implements Exception { final String message; final bool duplicate; }`
  - `abstract interface class Repository` com: `Stream<List<Space>> watchSpaces()`, `Future<void> upsertSpace(Space)`, `Future<void> deleteSpace(String id)`, `Stream<List<Note>> watchNotes()`, `Future<void> upsertNote(Note)`, `Future<void> deleteNote(String id)`, `Stream<List<TaskItem>> watchTasks()`, `Future<void> upsertTask(TaskItem)`, `Future<void> deleteTask(String id)`, `Stream<List<CalendarEvent>> watchEvents({required DateTime from})` (eventos com `endsAt >= from`), `Future<void> upsertEvent(CalendarEvent)`, `Future<void> deleteEvent(String id)`
  - `class MemoryRepository implements Repository` com `bool failWrites` (true → toda escrita lança `RepositoryException`)
  - `class SupabaseRepository implements Repository` com construtor `SupabaseRepository(SupabaseClient db)`

- [x] **Step 1: Escrever o teste do repositório em memória**

Create `app/test/data/memory_repository_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/space.dart';
import 'package:organizacional/domain/task_item.dart';

void main() {
  late MemoryRepository repo;
  setUp(() => repo = MemoryRepository());

  test('watch emite o estado atual e cada mudança', () async {
    final emissions = <List<Space>>[];
    final sub = repo.watchSpaces().listen(emissions.add);
    await Future<void>.delayed(Duration.zero);
    await repo.upsertSpace(const Space(id: 's1', name: 'Cálculo I', kind: SpaceKind.materia));
    await Future<void>.delayed(Duration.zero);
    expect(emissions.map((e) => e.length), [0, 1]);
    await sub.cancel();
  });

  test('excluir espaço apaga notas e tarefas e mantém eventos sem espaço', () async {
    await repo.upsertSpace(const Space(id: 's1', name: 'Cálculo I'));
    await repo.upsertNote(const Note(id: 'n1', title: 'Limites', spaceId: 's1'));
    await repo.upsertTask(const TaskItem(id: 't1', title: 'Lista 1', spaceId: 's1'));
    await repo.upsertEvent(CalendarEvent(
      id: 'e1',
      title: 'Aula',
      startsAt: DateTime(2026, 9, 28, 8),
      endsAt: DateTime(2026, 9, 28, 10),
      spaceId: 's1',
    ));
    await repo.deleteSpace('s1');
    expect(await repo.watchNotes().first, isEmpty);
    expect(await repo.watchTasks().first, isEmpty);
    final events = await repo.watchEvents(from: DateTime(2026, 9, 1)).first;
    expect(events.single.spaceId, isNull);
  });

  test('título de nota duplicado (caixa/espaços) lança duplicate', () async {
    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo I'));
    await expectLater(
      repo.upsertNote(const Note(id: 'n2', title: '  cálculo   i ')),
      throwsA(isA<RepositoryException>().having((e) => e.duplicate, 'duplicate', isTrue)),
    );
  });

  test('regravar a própria nota com o mesmo título não é duplicata', () async {
    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo I'));
    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo I', body: 'novo'));
    expect((await repo.watchNotes().first).single.body, 'novo');
  });

  test('failWrites simula queda de conexão', () async {
    repo.failWrites = true;
    await expectLater(
      repo.upsertTask(const TaskItem(id: 't1', title: 'x')),
      throwsA(isA<RepositoryException>()),
    );
    expect(await repo.watchTasks().first, isEmpty);
  });

  test('watchEvents ignora eventos que terminaram antes de from', () async {
    await repo.upsertEvent(CalendarEvent(
      id: 'velho',
      title: 'Velho',
      startsAt: DateTime(2026, 9, 1, 8),
      endsAt: DateTime(2026, 9, 1, 9),
    ));
    await repo.upsertEvent(CalendarEvent(
      id: 'novo',
      title: 'Novo',
      startsAt: DateTime(2026, 9, 28, 8),
      endsAt: DateTime(2026, 9, 28, 9),
    ));
    final events = await repo.watchEvents(from: DateTime(2026, 9, 28)).first;
    expect(events.map((e) => e.id), ['novo']);
  });
}
```

- [x] **Step 2: Rodar e ver falhar**

Run: `cd app && TZ=America/Sao_Paulo flutter test test/data/memory_repository_test.dart`
Expected: FAIL (`memory_repository.dart` não existe).

- [x] **Step 3: Implementar a interface e o repositório em memória**

Create `app/lib/data/repository.dart`:
```dart
import '../domain/calendar_event.dart';
import '../domain/note.dart';
import '../domain/space.dart';
import '../domain/task_item.dart';

class RepositoryException implements Exception {
  const RepositoryException(this.message, {this.duplicate = false});

  final String message;
  final bool duplicate;

  @override
  String toString() => 'RepositoryException: $message';
}

abstract interface class Repository {
  Stream<List<Space>> watchSpaces();
  Future<void> upsertSpace(Space space);
  Future<void> deleteSpace(String id);

  Stream<List<Note>> watchNotes();
  Future<void> upsertNote(Note note);
  Future<void> deleteNote(String id);

  Stream<List<TaskItem>> watchTasks();
  Future<void> upsertTask(TaskItem task);
  Future<void> deleteTask(String id);

  /// Eventos que terminam em [from] ou depois.
  Stream<List<CalendarEvent>> watchEvents({required DateTime from});
  Future<void> upsertEvent(CalendarEvent event);
  Future<void> deleteEvent(String id);
}
```

Create `app/lib/data/memory_repository.dart`:
```dart
import 'dart:async';

import '../domain/calendar_event.dart';
import '../domain/note.dart';
import '../domain/space.dart';
import '../domain/task_item.dart';
import '../domain/wikilinks.dart';
import 'repository.dart';

/// Implementação em memória usada nos testes. Reproduz as regras do banco
/// (título único, cascade ao excluir espaço).
class MemoryRepository implements Repository {
  final _spaces = <String, Space>{};
  final _notes = <String, Note>{};
  final _tasks = <String, TaskItem>{};
  final _events = <String, CalendarEvent>{};
  final _changes = StreamController<void>.broadcast(sync: true);

  /// Quando true, toda escrita falha, simulando uma queda de conexão.
  bool failWrites = false;

  Stream<List<T>> _watch<T>(List<T> Function() snapshot) {
    StreamSubscription<void>? sub;
    late final StreamController<List<T>> controller;
    controller = StreamController<List<T>>(
      onListen: () {
        controller.add(snapshot());
        sub = _changes.stream.listen((_) => controller.add(snapshot()));
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  Future<void> _write(void Function() change) async {
    if (failWrites) throw const RepositoryException('Sem conexão (simulado)');
    change();
    _changes.add(null);
  }

  @override
  Stream<List<Space>> watchSpaces() => _watch(
      () => _spaces.values.toList()..sort((a, b) => a.position.compareTo(b.position)));

  @override
  Future<void> upsertSpace(Space space) => _write(() => _spaces[space.id] = space);

  @override
  Future<void> deleteSpace(String id) => _write(() {
        _spaces.remove(id);
        _notes.removeWhere((_, n) => n.spaceId == id);
        _tasks.removeWhere((_, t) => t.spaceId == id);
        for (final e in _events.values.where((e) => e.spaceId == id).toList()) {
          _events[e.id] = e.withoutSpace();
        }
      });

  @override
  Stream<List<Note>> watchNotes() =>
      _watch(() => _notes.values.toList()..sort((a, b) => a.title.compareTo(b.title)));

  @override
  Future<void> upsertNote(Note note) async {
    final key = normalizeTitle(note.title);
    final clash = _notes.values.any((n) => n.id != note.id && normalizeTitle(n.title) == key);
    if (clash) {
      throw RepositoryException('Já existe uma nota "${note.title}"', duplicate: true);
    }
    return _write(() => _notes[note.id] = note);
  }

  @override
  Future<void> deleteNote(String id) => _write(() => _notes.remove(id));

  @override
  Stream<List<TaskItem>> watchTasks() => _watch(() => _tasks.values.toList());

  @override
  Future<void> upsertTask(TaskItem task) => _write(() => _tasks[task.id] = task);

  @override
  Future<void> deleteTask(String id) => _write(() => _tasks.remove(id));

  @override
  Stream<List<CalendarEvent>> watchEvents({required DateTime from}) => _watch(() =>
      _events.values.where((e) => !e.endsAt.isBefore(from)).toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt)));

  @override
  Future<void> upsertEvent(CalendarEvent event) => _write(() => _events[event.id] = event);

  @override
  Future<void> deleteEvent(String id) => _write(() => _events.remove(id));
}
```

- [x] **Step 4: Rodar e ver passar**

Run: `TZ=America/Sao_Paulo flutter test test/data/memory_repository_test.dart`
Expected: `All tests passed!`

- [x] **Step 5: Escrever o teste de integração do Supabase**

Create `app/test/data/supabase_repository_test.dart`:
```dart
@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/data/supabase_repository.dart';
import 'package:organizacional/domain/ids.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/space.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final url = Platform.environment['SUPABASE_URL'];
  final key = Platform.environment['SUPABASE_ANON_KEY'];
  final skip = url == null || key == null ? 'defina SUPABASE_URL e SUPABASE_ANON_KEY' : null;
  late SupabaseRepository repo;

  setUpAll(() async {
    if (skip != null) return;
    final client = SupabaseClient(url!, key!);
    await client.auth.signUp(
      email: 'teste-${DateTime.now().microsecondsSinceEpoch}@local.test',
      password: 'senha-de-teste-123',
    );
    repo = SupabaseRepository(client);
  });

  test('espaço criado chega pelo stream realtime', () async {
    final space = Space(id: newId(), name: 'Integração', kind: SpaceKind.materia);
    await repo.upsertSpace(space);
    final list = await repo
        .watchSpaces()
        .firstWhere((l) => l.any((s) => s.id == space.id))
        .timeout(const Duration(seconds: 10));
    expect(list.firstWhere((s) => s.id == space.id), space);
  }, skip: skip);

  test('título duplicado vira RepositoryException(duplicate: true)', () async {
    final title = 'Duplicada ${newId()}';
    await repo.upsertNote(Note(id: newId(), title: title));
    await expectLater(
      repo.upsertNote(Note(id: newId(), title: title.toUpperCase())),
      throwsA(isA<RepositoryException>().having((e) => e.duplicate, 'duplicate', isTrue)),
    );
  }, skip: skip);
}
```

- [x] **Step 6: Implementar o repositório Supabase**

Create `app/lib/data/supabase_repository.dart`:
```dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/calendar_event.dart';
import '../domain/note.dart';
import '../domain/space.dart';
import '../domain/task_item.dart';
import 'repository.dart';

class SupabaseRepository implements Repository {
  SupabaseRepository(this._db);

  final SupabaseClient _db;

  Stream<List<T>> _watch<T>(
    String table,
    T Function(Map<String, dynamic>) fromMap,
    String orderBy,
  ) =>
      _db
          .from(table)
          .stream(primaryKey: ['id'])
          .order(orderBy, ascending: true)
          .map((rows) => rows.map(fromMap).toList());

  Future<void> _guard(Future<void> Function() op) async {
    try {
      await op();
    } on PostgrestException catch (e) {
      throw RepositoryException(e.message, duplicate: e.code == '23505');
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException('Falha de conexão: $e');
    }
  }

  Future<void> _upsert(String table, Map<String, dynamic> row) =>
      _guard(() async => await _db.from(table).upsert(row));

  Future<void> _delete(String table, String id) =>
      _guard(() async => await _db.from(table).delete().eq('id', id));

  @override
  Stream<List<Space>> watchSpaces() => _watch('spaces', Space.fromMap, 'position');

  @override
  Future<void> upsertSpace(Space space) => _upsert('spaces', space.toMap());

  @override
  Future<void> deleteSpace(String id) => _delete('spaces', id);

  @override
  Stream<List<Note>> watchNotes() => _watch('notes', Note.fromMap, 'title');

  @override
  Future<void> upsertNote(Note note) => _upsert('notes', note.toMap());

  @override
  Future<void> deleteNote(String id) => _delete('notes', id);

  @override
  Stream<List<TaskItem>> watchTasks() => _watch('tasks', TaskItem.fromMap, 'created_at');

  @override
  Future<void> upsertTask(TaskItem task) => _upsert('tasks', task.toMap());

  @override
  Future<void> deleteTask(String id) => _delete('tasks', id);

  @override
  Stream<List<CalendarEvent>> watchEvents({required DateTime from}) => _db
      .from('events')
      .stream(primaryKey: ['id'])
      .gte('ends_at', from.toUtc().toIso8601String())
      .order('starts_at', ascending: true)
      .map((rows) => rows.map(CalendarEvent.fromMap).toList());

  @override
  Future<void> upsertEvent(CalendarEvent event) => _upsert('events', event.toMap());

  @override
  Future<void> deleteEvent(String id) => _delete('events', id);
}
```

- [x] **Step 7: Rodar a integração contra o Supabase local**

Run:
```bash
cd /home/only/organizacional && npx supabase start
eval "$(npx supabase status -o env)"
cd app && SUPABASE_URL="$API_URL" SUPABASE_ANON_KEY="$ANON_KEY" flutter test --tags integration
```
Expected: `All tests passed!` (2 testes, nenhum skipped). Se o `status -o env` da sua versão do CLI não exportar `ANON_KEY`, copie a chave anon/publishable de `npx supabase status`.

- [x] **Step 8: Rodar a suíte rápida e o analyzer**

Run: `TZ=America/Sao_Paulo flutter test --exclude-tags integration && flutter analyze`
Expected: `All tests passed!`; `No issues found!`

- [x] **Step 9: Commit**

```bash
cd /home/only/organizacional
git add app/lib/data app/test/data
git commit -m "feat: repositórios em memória e Supabase"
```

---

### Task 5: Shell do app — tema, rotas, navegação, login e componentes compartilhados

**Files:**
- Create: `app/lib/app/{app,theme,router,shell,providers}.dart`
- Create: `app/lib/ui/{common,task_tile,event_tile}.dart`
- Create: `app/lib/features/auth/login_screen.dart`
- Create (versões iniciais, substituídas nas Tasks 6–8): `app/lib/features/today/today_screen.dart`, `agenda/agenda_screen.dart`, `tasks/tasks_screen.dart`, `spaces/spaces_screen.dart`, `spaces/space_screen.dart`, `notes/note_screen.dart`
- Modify: `app/lib/main.dart` (substituir tudo), `app/android/app/src/main/AndroidManifest.xml`
- Create: `app/env.example.json`, `app/test/helpers.dart`
- Test: `app/test/app/shell_test.dart`, `app/test/ui/task_tile_test.dart`

**Interfaces:**
- Consumes: `Repository`, `RepositoryException`, `SupabaseRepository` (Task 4); modelos (Task 2).
- Produces:
  - `final repositoryProvider = Provider<Repository>`, `final clockProvider = Provider<DateTime Function()>`, `final spacesProvider = StreamProvider<List<Space>>`, `final notesProvider = StreamProvider<List<Note>>`, `final tasksProvider = StreamProvider<List<TaskItem>>`, `final eventsFromProvider = StreamProvider.family<List<CalendarEvent>, DateTime>`
  - `GoRouter buildRouter({String initialLocation = '/', required bool Function() isSignedIn, Listenable? refresh})`. Rotas: `/login`, `/`, `/agenda`, `/tarefas`, `/espacos`, `/espacos/:id` → `SpaceScreen(spaceId:)`, `/nota/:id` → `NoteScreen(key: ValueKey(id), noteId:)`
  - `class OrganizacionalApp({required GoRouter router})`, `ThemeData buildTheme(Brightness)`
  - `Widget asyncView<T>(AsyncValue<T>, Widget Function(T))`, `class SectionHeader(String)`, `class EmptyHint(String)`, `String plural(int n, String one, String many)`, `void showError(BuildContext, String)`
  - `class TaskTile({required TaskItem task, String? spaceName})`: checkbox com key `ValueKey('task-check-<id>')`
  - `class EventTile({required CalendarEvent event, String? spaceName})`: subtítulo `HH:mm–HH:mm` (ou `Dia todo`) · espaço · local
  - Teste: `Future<void> pumpApp(WidgetTester, Repository, {String location = '/', DateTime? now, Size size = const Size(1000, 800)})`. Sem `now`, usa `DateTime(2026, 9, 28, 10)` (segunda-feira).
  - Títulos de AppBar fixos, dos quais os testes dependem: Tarefas → `'Tarefas'`, Espaços → `'Espaços'`.

- [x] **Step 1: Escrever os testes**

Create `app/test/helpers.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/app/app.dart';
import 'package:organizacional/app/providers.dart';
import 'package:organizacional/app/router.dart';
import 'package:organizacional/data/repository.dart';

final defaultNow = DateTime(2026, 9, 28, 10); // segunda-feira

Future<void> pumpApp(
  WidgetTester tester,
  Repository repo, {
  String location = '/',
  DateTime? now,
  Size size = const Size(1000, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      clockProvider.overrideWithValue(() => now ?? defaultNow),
    ],
    child: OrganizacionalApp(
      router: buildRouter(initialLocation: location, isSignedIn: () => true),
    ),
  ));
  await tester.pumpAndSettle();
}
```

Create `app/test/app/shell_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';

import '../helpers.dart';

void main() {
  testWidgets('tela larga usa NavigationRail e navega', (tester) async {
    await pumpApp(tester, MemoryRepository(), size: const Size(1000, 800));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.text('Tarefas'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Tarefas'), findsOneWidget);
  });

  testWidgets('tela de celular usa NavigationBar inferior', (tester) async {
    await pumpApp(tester, MemoryRepository(), size: const Size(400, 800));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    await tester.tap(find.text('Espaços'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Espaços'), findsOneWidget);
  });
}
```

Create `app/test/ui/task_tile_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/app/providers.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/task_item.dart';
import 'package:organizacional/ui/task_tile.dart';

void main() {
  const task = TaskItem(id: 't1', title: 'Lista 1');
  final now = DateTime(2026, 9, 28, 10);

  Future<MemoryRepository> pump(WidgetTester tester) async {
    final repo = MemoryRepository();
    await repo.upsertTask(task);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        clockProvider.overrideWithValue(() => now),
      ],
      child: const MaterialApp(home: Scaffold(body: TaskTile(task: task))),
    ));
    return repo;
  }

  testWidgets('marcar a caixa conclui a tarefa com a hora atual', (tester) async {
    final repo = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('task-check-t1')));
    await tester.pump();
    final saved = (await repo.watchTasks().first).single;
    expect(saved.isDone, isTrue);
    expect(saved.completedAt, now);
  });

  testWidgets('falha ao salvar mostra aviso', (tester) async {
    final repo = await pump(tester);
    repo.failWrites = true;
    await tester.tap(find.byKey(const ValueKey('task-check-t1')));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível atualizar a tarefa.'), findsOneWidget);
  });
}
```

- [x] **Step 2: Rodar e ver falhar**

Run: `cd app && TZ=America/Sao_Paulo flutter test test/app test/ui`
Expected: FAIL (arquivos `app/*.dart` e `ui/*.dart` não existem).

- [x] **Step 3: Providers, tema, componentes compartilhados**

Create `app/lib/app/providers.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repository.dart';
import '../domain/calendar_event.dart';
import '../domain/note.dart';
import '../domain/space.dart';
import '../domain/task_item.dart';

final repositoryProvider = Provider<Repository>(
  (ref) => throw UnimplementedError('repositoryProvider precisa de override'),
);

final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final spacesProvider =
    StreamProvider<List<Space>>((ref) => ref.watch(repositoryProvider).watchSpaces());

final notesProvider =
    StreamProvider<List<Note>>((ref) => ref.watch(repositoryProvider).watchNotes());

final tasksProvider =
    StreamProvider<List<TaskItem>>((ref) => ref.watch(repositoryProvider).watchTasks());

final eventsFromProvider = StreamProvider.family<List<CalendarEvent>, DateTime>(
  (ref, from) => ref.watch(repositoryProvider).watchEvents(from: from),
);
```

Create `app/lib/app/theme.dart`:
```dart
import 'package:flutter/material.dart';

ThemeData buildTheme(Brightness brightness) => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF55606E),
        brightness: brightness,
      ),
    );
```

Create `app/lib/ui/common.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Widget asyncView<T>(AsyncValue<T> value, Widget Function(T data) builder) => value.when(
      data: builder,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Erro ao carregar: $error', textAlign: TextAlign.center),
        ),
      ),
    );

String plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

void showError(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}

class EmptyHint extends StatelessWidget {
  const EmptyHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
```

Create `app/lib/ui/task_tile.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app/providers.dart';
import '../data/repository.dart';
import '../domain/task_item.dart';
import 'common.dart';

class TaskTile extends ConsumerWidget {
  const TaskTile({super.key, required this.task, this.spaceName});

  final TaskItem task;
  final String? spaceName;

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final now = ref.read(clockProvider)();
    try {
      await ref.read(repositoryProvider).upsertTask(task.toggled(now));
    } on RepositoryException {
      if (context.mounted) showError(context, 'Não foi possível atualizar a tarefa.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final due = task.dueAt;
    final subtitle = [
      if (spaceName != null) spaceName!,
      if (due != null) DateFormat('d MMM', 'pt_BR').format(due),
    ].join(' · ');
    return ListTile(
      leading: Checkbox(
        key: ValueKey('task-check-${task.id}'),
        value: task.isDone,
        onChanged: (_) => _toggle(context, ref),
      ),
      title: Text(
        task.title,
        style: task.isDone
            ? TextStyle(
                decoration: TextDecoration.lineThrough,
                color: theme.colorScheme.onSurfaceVariant,
              )
            : null,
      ),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
    );
  }
}
```

Create `app/lib/ui/event_tile.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/calendar_event.dart';

class EventTile extends StatelessWidget {
  const EventTile({super.key, required this.event, this.spaceName});

  final CalendarEvent event;
  final String? spaceName;

  @override
  Widget build(BuildContext context) {
    final hm = DateFormat.Hm('pt_BR');
    final time = event.allDay
        ? 'Dia todo'
        : '${hm.format(event.startsAt)}–${hm.format(event.endsAt)}';
    final location = event.location;
    final details = [
      time,
      if (spaceName != null) spaceName!,
      if (location != null && location.isNotEmpty) location,
    ].join(' · ');
    return ListTile(
      leading: const Icon(Icons.event_outlined),
      title: Text(event.title),
      subtitle: Text(details),
    );
  }
}
```

- [x] **Step 4: Versões iniciais das telas (as Tasks 6–8 substituem cada arquivo por inteiro)**

Create `app/lib/features/today/today_screen.dart`:
```dart
import 'package:flutter/material.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text('Hoje')));
}
```

Create `app/lib/features/agenda/agenda_screen.dart`:
```dart
import 'package:flutter/material.dart';

class AgendaScreen extends StatelessWidget {
  const AgendaScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text('Agenda')));
}
```

Create `app/lib/features/tasks/tasks_screen.dart`:
```dart
import 'package:flutter/material.dart';

class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text('Tarefas')));
}
```

Create `app/lib/features/spaces/spaces_screen.dart`:
```dart
import 'package:flutter/material.dart';

class SpacesScreen extends StatelessWidget {
  const SpacesScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text('Espaços')));
}
```

Create `app/lib/features/spaces/space_screen.dart`:
```dart
import 'package:flutter/material.dart';

class SpaceScreen extends StatelessWidget {
  const SpaceScreen({super.key, required this.spaceId});

  final String spaceId;

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar());
}
```

Create `app/lib/features/notes/note_screen.dart`:
```dart
import 'package:flutter/material.dart';

class NoteScreen extends StatelessWidget {
  const NoteScreen({super.key, required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar());
}
```

- [x] **Step 5: Login, shell, rotas, app e main**

Create `app/lib/features/auth/login_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on AuthException {
      _error = 'E-mail ou senha incorretos.';
    } catch (_) {
      _error = 'Não foi possível conectar ao servidor.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Organizacional', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 24),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'E-mail'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  onSubmitted: (_) => _signIn(),
                  decoration: const InputDecoration(labelText: 'Senha'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _signIn,
                  child: const Text('Entrar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

Create `app/lib/app/shell.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  static const _destinations = [
    (path: '/', icon: Icons.today_outlined, label: 'Hoje'),
    (path: '/agenda', icon: Icons.calendar_month_outlined, label: 'Agenda'),
    (path: '/tarefas', icon: Icons.check_circle_outline, label: 'Tarefas'),
    (path: '/espacos', icon: Icons.folder_outlined, label: 'Espaços'),
  ];

  int get _index {
    if (location.startsWith('/agenda')) return 1;
    if (location.startsWith('/tarefas')) return 2;
    if (location.startsWith('/espacos') || location.startsWith('/nota')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    void go(int i) => context.go(_destinations[i].path);
    if (MediaQuery.sizeOf(context).width >= 720) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: go,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label)),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: go,
        destinations: [
          for (final d in _destinations)
            NavigationDestination(icon: Icon(d.icon), label: d.label),
        ],
      ),
    );
  }
}
```

Create `app/lib/app/router.dart`:
```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/agenda/agenda_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/notes/note_screen.dart';
import '../features/spaces/space_screen.dart';
import '../features/spaces/spaces_screen.dart';
import '../features/tasks/tasks_screen.dart';
import '../features/today/today_screen.dart';
import 'shell.dart';

/// Converte um Stream (ex.: mudanças de sessão) em Listenable para o go_router.
class StreamListenable extends ChangeNotifier {
  StreamListenable(Stream<Object?> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<Object?> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

GoRouter buildRouter({
  String initialLocation = '/',
  required bool Function() isSignedIn,
  Listenable? refresh,
}) =>
    GoRouter(
      initialLocation: initialLocation,
      refreshListenable: refresh,
      redirect: (context, state) {
        final atLogin = state.matchedLocation == '/login';
        if (!isSignedIn()) return atLogin ? null : '/login';
        if (atLogin) return '/';
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
        ShellRoute(
          builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
          routes: [
            GoRoute(path: '/', builder: (context, state) => const TodayScreen()),
            GoRoute(path: '/agenda', builder: (context, state) => const AgendaScreen()),
            GoRoute(path: '/tarefas', builder: (context, state) => const TasksScreen()),
            GoRoute(path: '/espacos', builder: (context, state) => const SpacesScreen()),
            GoRoute(
              path: '/espacos/:id',
              builder: (context, state) => SpaceScreen(spaceId: state.pathParameters['id']!),
            ),
            GoRoute(
              path: '/nota/:id',
              builder: (context, state) {
                final id = state.pathParameters['id']!;
                return NoteScreen(key: ValueKey(id), noteId: id);
              },
            ),
          ],
        ),
      ],
    );
```

Create `app/lib/app/app.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'theme.dart';

class OrganizacionalApp extends StatelessWidget {
  const OrganizacionalApp({super.key, required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'Organizacional',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        routerConfig: router,
      );
}
```

Replace all of `app/lib/main.dart` with:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'app/router.dart';
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
    overrides: [repositoryProvider.overrideWithValue(SupabaseRepository(client))],
    child: OrganizacionalApp(router: router),
  ));
}
```

Create `app/env.example.json`:
```json
{
  "SUPABASE_URL": "http://127.0.0.1:54321",
  "SUPABASE_ANON_KEY": "cole-aqui-a-chave-anon-de-npx-supabase-status"
}
```

Modify `app/android/app/src/main/AndroidManifest.xml`: add the permission line right after the opening `<manifest ...>` tag:
```xml
    <uses-permission android:name="android.permission.INTERNET"/>
```

- [x] **Step 6: Rodar e ver passar**

Run: `TZ=America/Sao_Paulo flutter test --exclude-tags integration && flutter analyze`
Expected: `All tests passed!`; `No issues found!`

- [x] **Step 7: Testar à mão no Linux contra o Supabase local**

Run:
```bash
cd /home/only/organizacional && npx supabase status   # copie API URL e anon key
cp app/env.example.json app/env.json                  # edite com a chave
# Crie seu usuário em http://127.0.0.1:54323 (Studio → Authentication → Add user)
cd app && flutter run -d linux --dart-define-from-file=env.json
```
Expected: a tela de login aparece; com e-mail/senha certos, o app abre em "Hoje" com o menu lateral; a janela estreita (< 720 px) mostra a barra inferior.

- [x] **Step 8: Commit**

```bash
cd /home/only/organizacional
git add app
git commit -m "feat: shell do app com login, rotas e navegação responsiva"
```

---

### Task 6: Espaços e notas (Markdown, `[[links]]`, backlinks)

**Files:**
- Replace: `app/lib/features/spaces/spaces_screen.dart`, `app/lib/features/spaces/space_screen.dart`, `app/lib/features/notes/note_screen.dart`
- Test: `app/test/features/spaces_test.dart`, `app/test/features/notes_test.dart`

**Interfaces:**
- Consumes: `repositoryProvider`, `spacesProvider`, `notesProvider`, `tasksProvider`, `clockProvider`; `asyncView`, `SectionHeader`, `EmptyHint`, `plural`, `showError`, `TaskTile` (Task 5); `newId`, `Space`, `SpaceKind`, `Note`; `resolveWikiLink`, `backlinksFor`, `wikiLinksToMarkdown`, `uniqueTitle` (Task 3); `pumpApp` (test helper).
- Produces: `SpacesScreen` (AppBar `'Espaços'`, FAB key `new-space`), `SpaceDialog` (campo key `space-name`, botão `Criar`), `SpaceScreen(spaceId)` (botões key `new-note` e `delete-space`), `NoteScreen(noteId)` (keys `note-title`, `note-body`, `toggle-preview`, `save-error`; autosave com debounce de 800 ms).

- [x] **Step 1: Escrever os testes**

Create `app/test/features/spaces_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/note.dart';
import 'package:organizacional/domain/space.dart';
import 'package:organizacional/domain/task_item.dart';

import '../helpers.dart';

void main() {
  testWidgets('cria um espaço de hobby pelo diálogo', (tester) async {
    final repo = MemoryRepository();
    await pumpApp(tester, repo, location: '/espacos');
    await tester.tap(find.byKey(const Key('new-space')));
    await tester.pumpAndSettle();
    final criar = find.widgetWithText(FilledButton, 'Criar');
    expect(tester.widget<FilledButton>(criar).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('space-name')), 'Violão');
    await tester.tap(find.text('Hobby'));
    await tester.pump();
    await tester.tap(criar);
    await tester.pumpAndSettle();
    expect(find.text('Hobbies'), findsOneWidget);
    expect(find.text('Violão'), findsOneWidget);
    expect((await repo.watchSpaces().first).single.kind, SpaceKind.hobby);
  });

  testWidgets('nova nota no espaço abre o editor com título único', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertSpace(const Space(id: 's1', name: 'Cálculo I', kind: SpaceKind.materia));
    await repo.upsertNote(const Note(id: 'n0', title: 'Sem título'));
    await pumpApp(tester, repo, location: '/espacos/s1');
    await tester.tap(find.byKey(const Key('new-note')));
    await tester.pumpAndSettle();
    final title = tester.widget<TextField>(find.byKey(const Key('note-title')));
    expect(title.controller!.text, 'Sem título 2');
    final created = (await repo.watchNotes().first).firstWhere((n) => n.id != 'n0');
    expect(created.spaceId, 's1');
  });

  testWidgets('excluir espaço confirma com a contagem e apaga o conteúdo', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertSpace(const Space(id: 's1', name: 'Cálculo I', kind: SpaceKind.materia));
    await repo.upsertNote(const Note(id: 'n1', title: 'Limites', spaceId: 's1'));
    await repo.upsertNote(const Note(id: 'n2', title: 'Derivadas', spaceId: 's1'));
    await repo.upsertTask(const TaskItem(id: 't1', title: 'Lista 1', spaceId: 's1'));
    await pumpApp(tester, repo, location: '/espacos/s1');
    expect(find.text('Limites'), findsOneWidget);
    await tester.tap(find.byKey(const Key('delete-space')));
    await tester.pumpAndSettle();
    expect(
      find.text('Isso apaga 2 notas e 1 tarefa. Os eventos da agenda são mantidos.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Espaços'), findsOneWidget);
    expect(await repo.watchSpaces().first, isEmpty);
    expect(await repo.watchNotes().first, isEmpty);
  });
}
```

Create `app/test/features/notes_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/note.dart';

import '../helpers.dart';

void main() {
  testWidgets('edição é salva automaticamente', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo'));
    await pumpApp(tester, repo, location: '/nota/n1');
    await tester.enterText(find.byKey(const Key('note-body')), '# Limites');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect((await repo.watchNotes().first).single.body, '# Limites');
  });

  testWidgets('falha ao salvar mantém o texto e mostra aviso até salvar de novo', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo'));
    await pumpApp(tester, repo, location: '/nota/n1');
    repo.failWrites = true;
    await tester.enterText(find.byKey(const Key('note-body')), 'derivadas parciais');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byKey(const Key('save-error')), findsOneWidget);
    expect(find.text('Não foi possível salvar. Suas alterações continuam aqui.'), findsOneWidget);
    expect(find.text('derivadas parciais'), findsOneWidget);

    repo.failWrites = false;
    await tester.enterText(find.byKey(const Key('note-body')), 'derivadas parciais!');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byKey(const Key('save-error')), findsNothing);
    expect((await repo.watchNotes().first).single.body, 'derivadas parciais!');
  });

  testWidgets('título duplicado mostra aviso específico', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo'));
    await repo.upsertNote(const Note(id: 'n2', title: 'Física'));
    await pumpApp(tester, repo, location: '/nota/n2');
    await tester.enterText(find.byKey(const Key('note-title')), '  cálculo ');
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Já existe uma nota com esse título.'), findsOneWidget);
  });

  testWidgets('link [[...]] inexistente cria a nota, abre e mostra o backlink', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertNote(const Note(id: 'n1', title: 'Cálculo', body: 'Ver [[Álgebra]]'));
    await pumpApp(tester, repo, location: '/nota/n1');
    await tester.tap(find.byKey(const Key('toggle-preview')));
    await tester.pumpAndSettle();
    await tester.tapOnText(find.textRange.ofSubstring('Álgebra'));
    await tester.pumpAndSettle();
    final notes = await repo.watchNotes().first;
    expect(notes.map((n) => n.title), containsAll(['Cálculo', 'Álgebra']));
    final title = tester.widget<TextField>(find.byKey(const Key('note-title')));
    expect(title.controller!.text, 'Álgebra');
    expect(find.text('Mencionada em'), findsOneWidget);
    expect(find.text('Cálculo'), findsOneWidget);
  });
}
```

- [x] **Step 2: Rodar e ver falhar**

Run: `cd app && TZ=America/Sao_Paulo flutter test test/features/spaces_test.dart test/features/notes_test.dart`
Expected: FAIL (as telas iniciais não têm `new-space`, `note-body` etc.).

- [x] **Step 3: Implementar a lista de espaços**

Replace all of `app/lib/features/spaces/spaces_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/ids.dart';
import '../../domain/space.dart';
import '../../ui/common.dart';

IconData iconForKind(SpaceKind kind) => switch (kind) {
      SpaceKind.materia => Icons.school_outlined,
      SpaceKind.trabalho => Icons.assignment_outlined,
      SpaceKind.hobby => Icons.palette_outlined,
      SpaceKind.geral => Icons.folder_outlined,
    };

class SpacesScreen extends ConsumerWidget {
  const SpacesScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref, List<Space> existing) async {
    final result = await showDialog<(String, SpaceKind)>(
      context: context,
      builder: (_) => const SpaceDialog(),
    );
    if (result == null) return;
    final (name, kind) = result;
    try {
      await ref
          .read(repositoryProvider)
          .upsertSpace(Space(id: newId(), name: name, kind: kind, position: existing.length));
    } on RepositoryException {
      if (context.mounted) showError(context, 'Não foi possível criar o espaço.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaces = ref.watch(spacesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Espaços')),
      floatingActionButton: FloatingActionButton(
        key: const Key('new-space'),
        tooltip: 'Novo espaço',
        onPressed: () => _create(context, ref, spaces.value ?? const []),
        child: const Icon(Icons.add),
      ),
      body: asyncView(spaces, (list) {
        if (list.isEmpty) {
          return const Center(
            child: EmptyHint('Crie um espaço para cada matéria, trabalho ou hobby.'),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final kind in SpaceKind.values)
              if (list.any((s) => s.kind == kind)) ...[
                SectionHeader(kind.plural),
                for (final s in list.where((s) => s.kind == kind))
                  ListTile(
                    leading: Icon(iconForKind(kind)),
                    title: Text(s.name),
                    onTap: () => context.go('/espacos/${s.id}'),
                  ),
              ],
          ],
        );
      }),
    );
  }
}

class SpaceDialog extends StatefulWidget {
  const SpaceDialog({super.key});

  @override
  State<SpaceDialog> createState() => _SpaceDialogState();
}

class _SpaceDialogState extends State<SpaceDialog> {
  final _name = TextEditingController();
  SpaceKind _kind = SpaceKind.materia;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = _name.text.trim();
    return AlertDialog(
      title: const Text('Novo espaço'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('space-name'),
            controller: _name,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Nome'),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in SpaceKind.values)
                ChoiceChip(
                  label: Text(k.singular),
                  selected: _kind == k,
                  onSelected: (_) => setState(() => _kind = k),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: name.isEmpty ? null : () => Navigator.of(context).pop((name, _kind)),
          child: const Text('Criar'),
        ),
      ],
    );
  }
}
```

- [x] **Step 4: Implementar a tela do espaço**

Replace all of `app/lib/features/spaces/space_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/ids.dart';
import '../../domain/note.dart';
import '../../domain/space.dart';
import '../../domain/task_item.dart';
import '../../domain/wikilinks.dart';
import '../../ui/common.dart';
import '../../ui/task_tile.dart';

class SpaceScreen extends ConsumerWidget {
  const SpaceScreen({super.key, required this.spaceId});

  final String spaceId;

  Future<void> _newNote(BuildContext context, WidgetRef ref, List<Note> all) async {
    final note = Note(id: newId(), title: uniqueTitle('Sem título', all), spaceId: spaceId);
    try {
      await ref.read(repositoryProvider).upsertNote(note);
      if (context.mounted) context.go('/nota/${note.id}');
    } on RepositoryException {
      if (context.mounted) showError(context, 'Não foi possível criar a nota.');
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Space space,
    List<Note> notes,
    List<TaskItem> tasks,
  ) async {
    final nNotes = notes.where((n) => n.spaceId == space.id).length;
    final nTasks = tasks.where((t) => t.spaceId == space.id).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Excluir “${space.name}”?'),
        content: Text(
          'Isso apaga ${plural(nNotes, 'nota', 'notas')} e ${plural(nTasks, 'tarefa', 'tarefas')}. '
          'Os eventos da agenda são mantidos.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(repositoryProvider).deleteSpace(space.id);
      if (context.mounted) context.go('/espacos');
    } on RepositoryException {
      if (context.mounted) showError(context, 'Não foi possível excluir o espaço.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaces = ref.watch(spacesProvider);
    final notes = ref.watch(notesProvider);
    final tasks = ref.watch(tasksProvider);
    return asyncView(spaces, (spaceList) {
      final space = spaceList.where((s) => s.id == spaceId).firstOrNull;
      if (space == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(child: EmptyHint('Espaço não encontrado.')),
        );
      }
      return Scaffold(
        appBar: AppBar(
          title: Text(space.name),
          actions: [
            IconButton(
              key: const Key('delete-space'),
              tooltip: 'Excluir espaço',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(
                context,
                ref,
                space,
                notes.value ?? const [],
                tasks.value ?? const [],
              ),
            ),
          ],
        ),
        body: asyncView(notes, (noteList) => asyncView(tasks, (taskList) {
              final spaceNotes = noteList.where((n) => n.spaceId == spaceId).toList();
              final openTasks =
                  taskList.where((t) => t.spaceId == spaceId && !t.isDone).toList();
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      const Expanded(child: SectionHeader('Notas')),
                      TextButton.icon(
                        key: const Key('new-note'),
                        onPressed: () => _newNote(context, ref, noteList),
                        icon: const Icon(Icons.add),
                        label: const Text('Nova nota'),
                      ),
                    ],
                  ),
                  if (spaceNotes.isEmpty) const EmptyHint('Nenhuma nota.'),
                  for (final n in spaceNotes)
                    ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(n.title),
                      onTap: () => context.go('/nota/${n.id}'),
                    ),
                  const SectionHeader('Tarefas abertas'),
                  if (openTasks.isEmpty) const EmptyHint('Nenhuma tarefa aberta.'),
                  for (final t in openTasks) TaskTile(key: ValueKey(t.id), task: t),
                ],
              );
            })),
      );
    });
  }
}
```

- [x] **Step 5: Implementar o editor de notas**

Replace all of `app/lib/features/notes/note_screen.dart`:
```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/ids.dart';
import '../../domain/note.dart';
import '../../domain/wikilinks.dart';
import '../../ui/common.dart';

class NoteScreen extends ConsumerStatefulWidget {
  const NoteScreen({super.key, required this.noteId});

  final String noteId;

  @override
  ConsumerState<NoteScreen> createState() => _NoteScreenState();
}

class _NoteScreenState extends ConsumerState<NoteScreen> {
  late final Repository _repo;
  final _title = TextEditingController();
  final _body = TextEditingController();
  Note? _note;
  Timer? _debounce;
  bool _preview = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(repositoryProvider);
  }

  @override
  void dispose() {
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      final pending = _edited();
      if (pending != null) unawaited(_repo.upsertNote(pending).catchError((Object _) {}));
    }
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Note? _edited() {
    final note = _note;
    final title = _title.text.trim();
    if (note == null || title.isEmpty) return null;
    return note.copyWith(title: title, body: _body.text);
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), _save);
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _saveError = 'O título não pode ficar vazio.');
      return;
    }
    final updated = _edited();
    if (updated == null) return;
    try {
      await _repo.upsertNote(updated);
      _note = updated;
      if (mounted) setState(() => _saveError = null);
    } on RepositoryException catch (e) {
      if (mounted) {
        setState(() => _saveError = e.duplicate
            ? 'Já existe uma nota com esse título.'
            : 'Não foi possível salvar. Suas alterações continuam aqui.');
      }
    }
  }

  Future<void> _openLink(String? href, List<Note> notes) async {
    if (href == null || !href.startsWith('wiki:')) return;
    final target = Uri.decodeComponent(href.substring('wiki:'.length));
    final existing = resolveWikiLink(target, notes);
    if (existing != null) {
      context.go('/nota/${existing.id}');
      return;
    }
    final created = Note(id: newId(), title: target, spaceId: _note?.spaceId);
    try {
      await _repo.upsertNote(created);
      if (mounted) context.go('/nota/${created.id}');
    } on RepositoryException {
      if (mounted) setState(() => _saveError = 'Não foi possível criar a nota “$target”.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(notesProvider);
    return asyncView(notes, (all) {
      final current = all.where((n) => n.id == widget.noteId).firstOrNull;
      if (_note == null && current != null) {
        _note = current;
        _title.text = current.title;
        _body.text = current.body;
      }
      final note = _note;
      if (note == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(child: EmptyHint('Nota não encontrada.')),
        );
      }
      final theme = Theme.of(context);
      final backlinks = backlinksFor(note.copyWith(title: _title.text), all);
      return Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              key: const Key('toggle-preview'),
              tooltip: _preview ? 'Editar' : 'Visualizar',
              icon: Icon(_preview ? Icons.edit_outlined : Icons.visibility_outlined),
              onPressed: () => setState(() => _preview = !_preview),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
          children: [
            TextField(
              key: const Key('note-title'),
              controller: _title,
              onChanged: (_) => _changed(),
              style: theme.textTheme.headlineSmall,
              decoration: const InputDecoration.collapsed(hintText: 'Título'),
            ),
            if (_saveError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _saveError!,
                  key: const Key('save-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            if (_preview)
              MarkdownBody(
                data: wikiLinksToMarkdown(_body.text),
                onTapLink: (text, href, title) => _openLink(href, all),
              )
            else
              TextField(
                key: const Key('note-body'),
                controller: _body,
                onChanged: (_) => _changed(),
                maxLines: null,
                minLines: 12,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration.collapsed(
                  hintText: 'Escreva em Markdown. Use [[Título]] para ligar notas.',
                ),
              ),
            if (backlinks.isNotEmpty) ...[
              const SectionHeader('Mencionada em'),
              for (final n in backlinks)
                ListTile(
                  leading: const Icon(Icons.link),
                  title: Text(n.title),
                  onTap: () => context.go('/nota/${n.id}'),
                ),
            ],
          ],
        ),
      );
    });
  }
}
```

- [x] **Step 6: Rodar e ver passar**

Run: `TZ=America/Sao_Paulo flutter test --exclude-tags integration && flutter analyze`
Expected: `All tests passed!`; `No issues found!`

- [x] **Step 7: Commit**

```bash
cd /home/only/organizacional
git add app/lib/features/spaces app/lib/features/notes app/test/features/spaces_test.dart app/test/features/notes_test.dart
git commit -m "feat: espaços e notas Markdown com wikilinks e backlinks"
```

---

### Task 7: Tarefas

**Files:**
- Replace: `app/lib/features/tasks/tasks_screen.dart`
- Test: `app/test/features/tasks_test.dart`

**Interfaces:**
- Consumes: `repositoryProvider`, `spacesProvider`, `tasksProvider`, `clockProvider`, `asyncView`, `SectionHeader`, `EmptyHint`, `showError`, `TaskTile` (Task 5); `groupTasks`, `TaskGroup` (Task 3); `TaskItem`, `newId` (Task 2).
- Produces: `TasksScreen` (AppBar `'Tarefas'`; campo key `quick-add`; botão key `show-done`; chips de filtro por espaço).

- [x] **Step 1: Escrever os testes**

Create `app/test/features/tasks_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/space.dart';
import 'package:organizacional/domain/task_item.dart';

import '../helpers.dart';

void main() {
  testWidgets('adiciona tarefa pelo campo rápido', (tester) async {
    final repo = MemoryRepository();
    await pumpApp(tester, repo, location: '/tarefas');
    await tester.enterText(find.byKey(const Key('quick-add')), 'Lista de cálculo');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Sem data'), findsOneWidget);
    expect(find.text('Lista de cálculo'), findsOneWidget);
    expect((await repo.watchTasks().first).single.title, 'Lista de cálculo');
  });

  testWidgets('texto em branco não cria tarefa', (tester) async {
    final repo = MemoryRepository();
    await pumpApp(tester, repo, location: '/tarefas');
    await tester.enterText(find.byKey(const Key('quick-add')), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(await repo.watchTasks().first, isEmpty);
  });

  testWidgets('falha ao adicionar mantém o texto no campo', (tester) async {
    final repo = MemoryRepository()..failWrites = true;
    await pumpApp(tester, repo, location: '/tarefas');
    await tester.enterText(find.byKey(const Key('quick-add')), 'Resumo');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível adicionar. O texto continua no campo.'), findsOneWidget);
    expect(find.text('Resumo'), findsOneWidget);
  });

  testWidgets('agrupa atrasadas, esconde concluídas e conclui pela caixa', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertTask(TaskItem(id: 'a', title: 'Relatório', dueAt: DateTime(2026, 9, 27, 23, 59)));
    await repo.upsertTask(TaskItem(
      id: 'b',
      title: 'Antiga',
      status: TaskStatus.done,
      completedAt: DateTime(2026, 9, 20),
    ));
    await pumpApp(tester, repo, location: '/tarefas');
    expect(find.text('Atrasadas'), findsOneWidget);
    expect(find.text('Relatório'), findsOneWidget);
    expect(find.text('Antiga'), findsNothing);

    await tester.tap(find.byKey(const Key('show-done')));
    await tester.pumpAndSettle();
    expect(find.text('Antiga'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('task-check-a')));
    await tester.pumpAndSettle();
    expect(find.text('Atrasadas'), findsNothing);
    expect(find.text('Concluídas'), findsOneWidget);
  });

  testWidgets('filtro por espaço mostra só as tarefas dele', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertSpace(const Space(id: 's1', name: 'Cálculo I', kind: SpaceKind.materia));
    await repo.upsertTask(const TaskItem(id: 'a', title: 'Lista 1', spaceId: 's1'));
    await repo.upsertTask(const TaskItem(id: 'b', title: 'Comprar cordas'));
    await pumpApp(tester, repo, location: '/tarefas');
    expect(find.text('Comprar cordas'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Cálculo I'));
    await tester.pumpAndSettle();
    expect(find.text('Lista 1'), findsOneWidget);
    expect(find.text('Comprar cordas'), findsNothing);
  });
}
```

- [x] **Step 2: Rodar e ver falhar**

Run: `cd app && TZ=America/Sao_Paulo flutter test test/features/tasks_test.dart`
Expected: FAIL (`quick-add` não encontrado).

- [x] **Step 3: Implementar**

Replace all of `app/lib/features/tasks/tasks_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/agenda.dart';
import '../../domain/ids.dart';
import '../../domain/task_item.dart';
import '../../ui/common.dart';
import '../../ui/task_tile.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  final _input = TextEditingController();
  DateTime? _due;
  String? _spaceFilter;
  bool _showDone = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final title = _input.text.trim();
    if (title.isEmpty) return;
    final task = TaskItem(id: newId(), title: title, dueAt: _due, spaceId: _spaceFilter);
    try {
      await ref.read(repositoryProvider).upsertTask(task);
      _input.clear();
      setState(() => _due = null);
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível adicionar. O texto continua no campo.');
    }
  }

  Future<void> _pickDue() async {
    final now = ref.read(clockProvider)();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() => _due = DateTime(picked.year, picked.month, picked.day, 23, 59));
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider)();
    final spaces = ref.watch(spacesProvider);
    final tasks = ref.watch(tasksProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tarefas'),
        actions: [
          IconButton(
            key: const Key('show-done'),
            tooltip: _showDone ? 'Ocultar concluídas' : 'Mostrar concluídas',
            icon: Icon(_showDone ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            onPressed: () => setState(() => _showDone = !_showDone),
          ),
        ],
      ),
      body: asyncView(spaces, (spaceList) => asyncView(tasks, (taskList) {
            final names = {for (final s in spaceList) s.id: s.name};
            final visible = _spaceFilter == null
                ? taskList
                : taskList.where((t) => t.spaceId == _spaceFilter);
            final groups = groupTasks(visible, now);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  key: const Key('quick-add'),
                  controller: _input,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _add(),
                  decoration: InputDecoration(
                    hintText: 'Adicionar tarefa…',
                    prefixIcon: const Icon(Icons.add),
                    suffixIcon: IconButton(
                      tooltip: 'Prazo',
                      icon: const Icon(Icons.event_outlined),
                      onPressed: _pickDue,
                    ),
                  ),
                ),
                if (_due != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: InputChip(
                        label: Text('Prazo: ${DateFormat('d MMM', 'pt_BR').format(_due!)}'),
                        onDeleted: () => setState(() => _due = null),
                      ),
                    ),
                  ),
                if (spaceList.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Todos'),
                          selected: _spaceFilter == null,
                          onSelected: (_) => setState(() => _spaceFilter = null),
                        ),
                        for (final s in spaceList)
                          ChoiceChip(
                            label: Text(s.name),
                            selected: _spaceFilter == s.id,
                            onSelected: (_) => setState(() => _spaceFilter = s.id),
                          ),
                      ],
                    ),
                  ),
                for (final group in TaskGroup.values)
                  if (groups[group]!.isNotEmpty && (group != TaskGroup.concluidas || _showDone)) ...[
                    SectionHeader(group.label),
                    for (final t in groups[group]!)
                      TaskTile(key: ValueKey(t.id), task: t, spaceName: names[t.spaceId]),
                  ],
                if (taskList.isEmpty)
                  const EmptyHint('Nenhuma tarefa ainda. Digite acima e pressione Enter.'),
              ],
            );
          })),
    );
  }
}
```

- [x] **Step 4: Rodar e ver passar**

Run: `TZ=America/Sao_Paulo flutter test --exclude-tags integration && flutter analyze`
Expected: `All tests passed!`; `No issues found!`

- [x] **Step 5: Commit**

```bash
cd /home/only/organizacional
git add app/lib/features/tasks app/test/features/tasks_test.dart
git commit -m "feat: tela de tarefas com adição rápida, grupos e filtro por espaço"
```

---

### Task 8: Hoje e Agenda semanal

**Files:**
- Replace: `app/lib/features/today/today_screen.dart`, `app/lib/features/agenda/agenda_screen.dart`
- Create: `app/lib/features/agenda/event_dialog.dart`
- Test: `app/test/features/today_test.dart`, `app/test/features/agenda_test.dart`

**Interfaces:**
- Consumes: `repositoryProvider`, `spacesProvider`, `tasksProvider`, `eventsFromProvider`, `clockProvider`, `asyncView`, `SectionHeader`, `EmptyHint`, `showError`, `TaskTile`, `EventTile` (Task 5); `buildDayAgenda`, `eventsOnDay`, `startOfDay`, `startOfWeek`, `validateEventTimes` (Task 3); `CalendarEvent`, `Space`, `newId` (Task 2).
- Produces: `TodayScreen` (título no formato `"EEEE, d 'de' MMMM"` pt_BR); `AgendaScreen` (keys `prev-week`, `next-week`, `new-event`; cabeçalho do dia no formato `"EEEE, dd/MM"`); `EventDialog({required DateTime initialDay, required List<Space> spaces})`, que devolve um `CalendarEvent` via `Navigator.pop` (campo key `event-title`, botão `Salvar`).

- [x] **Step 1: Escrever os testes**

Create `app/test/features/today_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/calendar_event.dart';
import 'package:organizacional/domain/task_item.dart';

import '../helpers.dart';

void main() {
  testWidgets('Hoje mostra aulas do dia, atrasadas e tarefas de hoje', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertEvent(CalendarEvent(
      id: 'e1',
      title: 'Cálculo I',
      startsAt: DateTime(2026, 9, 28, 8),
      endsAt: DateTime(2026, 9, 28, 9, 40),
    ));
    await repo.upsertEvent(CalendarEvent(
      id: 'e2',
      title: 'Aula de amanhã',
      startsAt: DateTime(2026, 9, 29, 8),
      endsAt: DateTime(2026, 9, 29, 9),
    ));
    await repo.upsertTask(TaskItem(id: 't1', title: 'Lista 3', dueAt: DateTime(2026, 9, 28, 23, 59)));
    await repo.upsertTask(TaskItem(id: 't2', title: 'Resumo atrasado', dueAt: DateTime(2026, 9, 26, 23, 59)));
    await repo.upsertTask(TaskItem(id: 't3', title: 'Prova semana que vem', dueAt: DateTime(2026, 10, 5, 23, 59)));

    await pumpApp(tester, repo, now: DateTime(2026, 9, 28, 10));

    expect(find.text('segunda-feira, 28 de setembro'), findsOneWidget);
    expect(find.text('Cálculo I'), findsOneWidget);
    expect(find.text('08:00–09:40'), findsOneWidget);
    expect(find.text('Aula de amanhã'), findsNothing);
    expect(find.text('Atrasadas'), findsOneWidget);
    expect(find.text('Resumo atrasado'), findsOneWidget);
    expect(find.text('Lista 3'), findsOneWidget);
    expect(find.text('Prova semana que vem'), findsNothing);
  });

  testWidgets('Hoje vazio mostra dicas', (tester) async {
    await pumpApp(tester, MemoryRepository());
    expect(find.text('Nada na agenda hoje.'), findsOneWidget);
    expect(find.text('Nenhuma tarefa para hoje.'), findsOneWidget);
  });
}
```

Create `app/test/features/agenda_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/calendar_event.dart';

import '../helpers.dart';

void main() {
  testWidgets('mostra o evento no dia certo e navega entre semanas', (tester) async {
    final repo = MemoryRepository();
    await repo.upsertEvent(CalendarEvent(
      id: 'e1',
      title: 'Física',
      startsAt: DateTime(2026, 9, 30, 10),
      endsAt: DateTime(2026, 9, 30, 11, 40),
    ));
    await pumpApp(tester, repo, location: '/agenda');
    expect(find.text('quarta-feira, 30/09'), findsOneWidget);
    expect(find.text('Física'), findsOneWidget);

    await tester.tap(find.byKey(const Key('next-week')));
    await tester.pumpAndSettle();
    expect(find.text('Física'), findsNothing);
    expect(find.text('segunda-feira, 05/10'), findsOneWidget);

    await tester.tap(find.byKey(const Key('prev-week')));
    await tester.pumpAndSettle();
    expect(find.text('Física'), findsOneWidget);
  });

  testWidgets('novo evento pelo diálogo aparece na semana', (tester) async {
    final repo = MemoryRepository();
    await pumpApp(tester, repo, location: '/agenda');
    await tester.tap(find.byKey(const Key('new-event')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Salvar'));
    await tester.pump();
    expect(find.text('Dê um título ao evento.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('event-title')), 'Monitoria');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Monitoria'), findsOneWidget);
    final saved = (await repo.watchEvents(from: DateTime(2026, 9, 28)).first).single;
    expect(saved.startsAt, DateTime(2026, 9, 28, 8));
    expect(saved.endsAt, DateTime(2026, 9, 28, 9, 40));
  });
}
```

- [x] **Step 2: Rodar e ver falhar**

Run: `cd app && TZ=America/Sao_Paulo flutter test test/features/today_test.dart test/features/agenda_test.dart`
Expected: FAIL (as telas iniciais só têm o AppBar).

- [x] **Step 3: Implementar a tela Hoje**

Replace all of `app/lib/features/today/today_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../domain/agenda.dart';
import '../../ui/common.dart';
import '../../ui/event_tile.dart';
import '../../ui/task_tile.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final events = ref.watch(eventsFromProvider(startOfDay(now)));
    final tasks = ref.watch(tasksProvider);
    final spaces = ref.watch(spacesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(now))),
      body: asyncView(events, (eventList) => asyncView(tasks, (taskList) {
            final names = {for (final s in spaces.value ?? const []) s.id: s.name};
            final agenda = buildDayAgenda(now: now, events: eventList, tasks: taskList);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
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
              ],
            );
          })),
    );
  }
}
```

- [x] **Step 4: Implementar o diálogo de evento**

Create `app/lib/features/agenda/event_dialog.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/agenda.dart';
import '../../domain/calendar_event.dart';
import '../../domain/ids.dart';
import '../../domain/space.dart';

class EventDialog extends StatefulWidget {
  const EventDialog({super.key, required this.initialDay, required this.spaces});

  final DateTime initialDay;
  final List<Space> spaces;

  @override
  State<EventDialog> createState() => _EventDialogState();
}

class _EventDialogState extends State<EventDialog> {
  final _title = TextEditingController();
  late DateTime _day = startOfDay(widget.initialDay);
  TimeOfDay _start = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 9, minute: 40);
  String? _spaceId;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  DateTime _at(TimeOfDay t) => DateTime(_day.year, _day.month, _day.day, t.hour, t.minute);

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(_day.year - 1),
      lastDate: DateTime(_day.year + 5),
    );
    if (picked != null) setState(() => _day = picked);
  }

  Future<void> _pickTime({required bool start}) async {
    final picked = await showTimePicker(context: context, initialTime: start ? _start : _end);
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Dê um título ao evento.');
      return;
    }
    final start = _at(_start);
    final end = _at(_end);
    final problem = validateEventTimes(start, end);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop(CalendarEvent(
      id: newId(),
      title: title,
      startsAt: start,
      endsAt: end,
      spaceId: _spaceId,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hm = DateFormat.Hm('pt_BR');
    return AlertDialog(
      title: const Text('Novo evento'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('event-title'),
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Título'),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _pickDay,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(_day)),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () => _pickTime(start: true),
                  child: Text('Início ${hm.format(_at(_start))}'),
                ),
                TextButton(
                  onPressed: () => _pickTime(start: false),
                  child: Text('Fim ${hm.format(_at(_end))}'),
                ),
              ],
            ),
            if (widget.spaces.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in widget.spaces)
                    ChoiceChip(
                      label: Text(s.name),
                      selected: _spaceId == s.id,
                      onSelected: (selected) => setState(() => _spaceId = selected ? s.id : null),
                    ),
                ],
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _submit, child: const Text('Salvar')),
      ],
    );
  }
}
```

- [x] **Step 5: Implementar a Agenda semanal**

Replace all of `app/lib/features/agenda/agenda_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/agenda.dart';
import '../../domain/calendar_event.dart';
import '../../domain/space.dart';
import '../../ui/common.dart';
import '../../ui/event_tile.dart';
import 'event_dialog.dart';

class AgendaScreen extends ConsumerStatefulWidget {
  const AgendaScreen({super.key});

  @override
  ConsumerState<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends ConsumerState<AgendaScreen> {
  late DateTime _weekStart = startOfWeek(ref.read(clockProvider)());

  DateTime _dayOfWeek(int i) => DateTime(_weekStart.year, _weekStart.month, _weekStart.day + i);

  void _shift(int days) => setState(() => _weekStart = _dayOfWeek(days));

  Future<void> _newEvent(List<Space> spaces) async {
    final now = ref.read(clockProvider)();
    final inWeek = !now.isBefore(_weekStart) && now.isBefore(_dayOfWeek(7));
    final event = await showDialog<CalendarEvent>(
      context: context,
      builder: (_) => EventDialog(initialDay: inWeek ? now : _weekStart, spaces: spaces),
    );
    if (event == null) return;
    try {
      await ref.read(repositoryProvider).upsertEvent(event);
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível salvar o evento.');
    }
  }

  List<Widget> _day(DateTime day, List<CalendarEvent> events, Map<String, String> names) {
    final dayEvents = eventsOnDay(events, day);
    return [
      SectionHeader(DateFormat('EEEE, dd/MM', 'pt_BR').format(day)),
      if (dayEvents.isEmpty) const EmptyHint('—'),
      for (final e in dayEvents) EventTile(event: e, spaceName: names[e.spaceId]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(eventsFromProvider(_weekStart));
    final spaces = ref.watch(spacesProvider);
    final short = DateFormat('d MMM', 'pt_BR');
    return Scaffold(
      appBar: AppBar(
        title: Text('${short.format(_weekStart)} – ${short.format(_dayOfWeek(6))}'),
        actions: [
          IconButton(
            key: const Key('prev-week'),
            tooltip: 'Semana anterior',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _shift(-7),
          ),
          TextButton(
            onPressed: () => setState(() => _weekStart = startOfWeek(ref.read(clockProvider)())),
            child: const Text('Esta semana'),
          ),
          IconButton(
            key: const Key('next-week'),
            tooltip: 'Próxima semana',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _shift(7),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('new-event'),
        tooltip: 'Novo evento',
        onPressed: () => _newEvent(spaces.value ?? const []),
        child: const Icon(Icons.add),
      ),
      body: asyncView(events, (eventList) {
        final names = {for (final s in spaces.value ?? const <Space>[]) s.id: s.name};
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (var i = 0; i < 7; i++) ..._day(_dayOfWeek(i), eventList, names),
          ],
        );
      }),
    );
  }
}
```

- [x] **Step 6: Rodar e ver passar**

Run: `TZ=America/Sao_Paulo flutter test --exclude-tags integration && flutter analyze`
Expected: `All tests passed!`; `No issues found!`

- [x] **Step 7: Commit**

```bash
cd /home/only/organizacional
git add app/lib/features/today app/lib/features/agenda app/test/features/today_test.dart app/test/features/agenda_test.dart
git commit -m "feat: telas Hoje e Agenda semanal com criação de eventos"
```

---

### Task 9: Builds (Linux + Android), Supabase em produção e README

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: tudo que as tasks anteriores produziram.
- Produces: `app/build/linux/x64/release/bundle/organizacional`, `app/build/app/outputs/flutter-apk/app-release.apk`, projeto Supabase na nuvem com a migration aplicada.

- [x] **Step 1: Suíte completa verde antes de empacotar**

Run:
```bash
cd /home/only/organizacional && npx supabase test db
cd app && TZ=America/Sao_Paulo flutter test --exclude-tags integration && flutter analyze
```
Expected: pgTAP `Tests=8` PASS; `All tests passed!`; `No issues found!`

- [x] **Step 2: Subir o banco na nuvem**

Run (depois de criar um projeto grátis em https://supabase.com/dashboard):
```bash
cd /home/only/organizacional
npx supabase login
npx supabase link --project-ref <ref-do-projeto>
npx supabase db push
```
Expected: `Finished supabase db push.` No painel: **Authentication → Users → Add user** (seu e-mail/senha) e **Authentication → Sign In / Providers → desligar "Allow new users to sign up"**. Copie a URL e a chave anon/publishable de **Project Settings → API** para `app/env.json`.

- [x] **Step 3: Build Linux**

Run: `cd app && flutter build linux --release --dart-define-from-file=env.json && ./build/linux/x64/release/bundle/organizacional`
Expected: o app abre, você faz login e vê "Hoje".

- [x] **Step 4: Build Android**

Run: `flutter build apk --release --dart-define-from-file=env.json`
Expected: `✓ Built build/app/outputs/flutter-apk/app-release.apk`. Instale no celular (`adb install build/app/outputs/flutter-apk/app-release.apk` ou copie o arquivo). O template do Flutter assina o release com a chave de debug, o que basta para instalar fora da loja. Crie uma nota no PC e confira que ela aparece no celular em poucos segundos (realtime).

- [x] **Step 5: Escrever o README**

Create `README.md`:
````markdown
# Organizacional

Agenda, tarefas, matérias, trabalhos e hobbies num só lugar. Flutter (Linux/Windows/Android) + Supabase.

## Estrutura
- `supabase/`: migrations SQL e testes pgTAP (`npx supabase test db`)
- `app/`: app Flutter (`lib/domain` regras puras, `lib/data` repositórios, `lib/features` telas)
- `docs/superpowers/`: spec e planos por fase

## Desenvolvimento local
```bash
npx supabase start                 # precisa do Docker
npx supabase status                # URL e chave anon → app/env.json (modelo: app/env.example.json)
cd app
TZ=America/Sao_Paulo flutter test --exclude-tags integration
flutter run -d linux --dart-define-from-file=env.json
```
Usuário local: Studio em http://127.0.0.1:54323 → Authentication → Add user.
No emulador Android, use `http://10.0.2.2:54321` como SUPABASE_URL.

## Testes de integração (Supabase local)
```bash
eval "$(npx supabase status -o env)"
cd app && SUPABASE_URL="$API_URL" SUPABASE_ANON_KEY="$ANON_KEY" flutter test --tags integration
```

## Builds
```bash
cd app
flutter build linux --release --dart-define-from-file=env.json
flutter build apk --release --dart-define-from-file=env.json
```

## Próximas fases
Veja `docs/superpowers/specs/2026-09-28-organizacional-design.md`: Claude via MCP, Google Agenda, GitHub, anexos (YouTube/PDF/docx).
````

- [x] **Step 6: Commit**

```bash
cd /home/only/organizacional
git add README.md
git commit -m "docs: README com desenvolvimento, testes e builds"
```
