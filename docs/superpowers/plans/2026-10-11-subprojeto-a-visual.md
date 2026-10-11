# Sub-projeto A — Visual novo, Kanban, Calendário, Editor e Avisos — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refazer o front do app Organizacional com 10 temas escuros dos PDFs do usuário, navegação estilo Notion/Obsidian, Kanban, agenda em calendário (com eventos que atravessam a meia-noite), editor WYSIWYG de notas, quadro de avisos e ocultar/remover dispositivos da Alexa.

**Architecture:** Flutter + Riverpod + go_router (existentes). Tema = `OrgThemeSpec` (dados gerados dos PDFs) → `ThemeData` + `ThemeExtension<OrgTokens>`. Dados novos em Supabase (`user_settings`, `notices`) com repositórios em memória para testes. Regras puras em `lib/domain`. Editor `appflowy_editor` com Markdown como fonte da verdade. Ponte Node ganha o comando `delete_device`.

**Tech Stack:** Flutter 3.47 (`~/development/flutter/bin`), Dart, flutter_riverpod 3, go_router 18, supabase_flutter 2, google_fonts, appflowy_editor 6; Supabase/Postgres + pgTAP; Node 22 + TypeScript + vitest (bridge).

**Spec:** `docs/superpowers/specs/2026-10-11-subprojeto-a-visual-design.md` (dados dos temas: `docs/superpowers/specs/assets/themes-10.json`).

## Global Constraints

- Todo texto de interface em **pt-BR**.
- Só tema **escuro**; 10 ids exatos: `violeta, safira, musgo, lunar, indigo, grafite, coral, cobalto, cacto, bronze`. Padrão `violeta`. Id desconhecido → `violeta`.
- Cores só via `Theme.of(context)` / `OrgTokens`; nenhuma tela usa `Color(0x…)` literal (exceto `lib/ui/themes.dart`).
- `accent` puro nunca como cor de texto; texto de destaque = `accentText`.
- Markdown continua sendo o formato salvo em `notes.body`.
- Breakpoint computador/celular: largura **≥ 720px** = computador (igual ao `AppShell` atual).
- Falha de gravação nunca apaga o que o usuário digitou.
- Testes: `cd app && TZ=America/Sao_Paulo ~/development/flutter/bin/flutter test --exclude-tags integration`; `flutter analyze` sem issues. Bridge: `cd bridge && npx vitest run` e `npx tsc -p tsconfig.typecheck.json --noEmit`. Banco: `npx supabase test db` (Supabase local já rodando; aplicar migração nova com `npx supabase migration up --local`).
- PATH: `export PATH="$HOME/development/flutter/bin:$PATH"`.
- **Subagentes não fazem `git commit`** (vários trabalham no mesmo worktree); o coordenador commita ao fim de cada onda.

## Review Focus

1. Evento 23:30 → 00:15 criado pelo diálogo: deve salvar com término no dia seguinte e aparecer nos dois dias (Task 6 tem o teste).
2. Nota com `[[Link]]`, checklist e título salva por um editor que nunca a modificou: o Markdown no banco não pode mudar só por abrir (Task 7, teste de ida e volta + "abrir e fechar não grava").
3. Tema salvo com id inexistente (`'neon'`) ou linha ausente em `user_settings`: app abre em Violeta sem erro (Task 1 + Task 2).
4. Aviso do usuário expirado ontem ou arquivado: não aparece na Home; aviso fixado aparece antes de um de prioridade alta (Task 1, `activeNotices`).
5. Arrastar cartão para "Feito" e de volta para "A fazer": `completedAt` definido e depois limpo (Task 1 `moveTask` + Task 5 widget).

---

## Onda 1 (Tasks 1 e 3 em paralelo; Task 2 depois da 1)

### Task 1: Dados — migração, modelos, repositórios, providers

**Files:**
- Create: `supabase/migrations/20261011000000_ui_redesign.sql`, `supabase/tests/database/ui_redesign_test.sql`
- Create: `app/lib/domain/notice.dart`, `app/lib/domain/user_settings.dart`, `app/lib/domain/system_notices.dart`
- Create: `app/lib/data/settings_repository.dart`, `app/lib/data/memory_settings_repository.dart`, `app/lib/data/supabase_settings_repository.dart`
- Modify: `app/lib/domain/task_item.dart` (add `moved`), `app/lib/domain/agenda.dart` (add `resolveEventEnd`)
- Modify: `app/lib/data/repository.dart`, `memory_repository.dart`, `supabase_repository.dart` (notices)
- Modify: `app/lib/app/providers.dart` (novos providers), `app/lib/main.dart` (override), `app/test/helpers.dart` (override + parâmetro `settings`)
- Test: `app/test/domain/notice_test.dart`, `app/test/domain/system_notices_test.dart`, `app/test/domain/user_settings_test.dart`, acrescentar em `app/test/domain/agenda_test.dart` e `models_test.dart`, `app/test/data/memory_settings_repository_test.dart`, acrescentar notices em `app/test/data/memory_repository_test.dart`

**Interfaces — Produces (usadas pelas Tasks 2, 4, 5, 6, 8):**
```dart
// domain/notice.dart
enum NoticePriority { normal, alta }
class Notice {
  const Notice({required this.id, required this.title, this.body = '', this.priority = NoticePriority.normal,
      this.pinned = false, this.expiresAt, this.archivedAt, this.createdAt});
  final String id; final String title; final String body; final NoticePriority priority;
  final bool pinned; final DateTime? expiresAt; final DateTime? archivedAt; final DateTime? createdAt;
  factory Notice.fromMap(Map<String, dynamic> m); Map<String, dynamic> toMap();
  Notice copyWith({String? title, String? body, NoticePriority? priority, bool? pinned,
      DateTime? expiresAt, bool clearExpires = false, DateTime? archivedAt});
}
List<Notice> activeNotices(Iterable<Notice> notices, DateTime now);
// domain/system_notices.dart
class SystemNotice { const SystemNotice({required this.id, required this.text, this.route}); final String id; final String text; final String? route; }
List<SystemNotice> systemNotices({required DateTime now, required Iterable<TaskItem> tasks,
    required BridgeStatus? bridge, required List<WakePlan> wakePlans});
// domain/user_settings.dart
const themeIds = ['violeta','safira','musgo','lunar','indigo','grafite','coral','cobalto','cacto','bronze'];
class UserSettings {
  const UserSettings({this.theme = 'violeta', this.hiddenAlexaDevices = const []});
  final String theme; final List<String> hiddenAlexaDevices;
  factory UserSettings.fromMap(Map<String, dynamic> m); Map<String, dynamic> toMap();
  UserSettings copyWith({String? theme, List<String>? hiddenAlexaDevices});
}
// domain/task_item.dart
TaskItem moved(TaskStatus status, DateTime now); // método de TaskItem
// domain/agenda.dart
DateTime resolveEventEnd(DateTime start, DateTime endDay, int endHour, int endMinute);
// data/settings_repository.dart
abstract interface class SettingsRepository { Stream<UserSettings> watchSettings(); Future<void> saveSettings(UserSettings s); }
// data/repository.dart (+)
Stream<List<Notice>> watchNotices(); Future<void> upsertNotice(Notice n); Future<void> deleteNotice(String id);
// app/providers.dart (+)
final settingsRepositoryProvider = Provider<SettingsRepository>(...throw UnimplementedError...);
final settingsProvider = StreamProvider<UserSettings>(...);
final noticesProvider = StreamProvider<List<Notice>>(...);
// test/helpers.dart: pumpApp(..., SettingsRepository? settings) — default MemorySettingsRepository()
```

- [ ] **Step 1: Migração SQL**

```sql
-- supabase/migrations/20261011000000_ui_redesign.sql
create table public.user_settings (
  user_id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  theme text not null default 'violeta'
    check (theme in ('violeta','safira','musgo','lunar','indigo','grafite','coral','cobalto','cacto','bronze')),
  hidden_alexa_devices text[] not null default '{}',
  updated_at timestamptz not null default now()
);
create table public.notices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title text not null check (length(btrim(title)) > 0),
  body text not null default '',
  priority text not null default 'normal' check (priority in ('normal', 'alta')),
  pinned boolean not null default false,
  expires_at timestamptz,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index notices_active_idx on public.notices (user_id, archived_at);
create trigger touch_updated_at before update on public.user_settings
  for each row execute function public.touch_updated_at();
create trigger touch_updated_at before update on public.notices
  for each row execute function public.touch_updated_at();
alter table public.user_settings enable row level security;
alter table public.notices enable row level security;
create policy "dono" on public.user_settings for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "dono" on public.notices for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
alter publication supabase_realtime add table public.user_settings, public.notices;
alter table public.alexa_commands drop constraint alexa_commands_kind_check;
alter table public.alexa_commands add constraint alexa_commands_kind_check
  check (kind in ('device', 'routine', 'speak', 'music', 'sync', 'wake_test', 'delete_device'));
```
Antes de escrever, confira em `supabase/migrations/20260928000000_core_schema.sql` e `20260930000000_alexa.sql` o nome real da função de trigger, como a publicação realtime é configurada e o nome real do check de `alexa_commands.kind` (`\d public.alexa_commands` no psql local: `psql postgresql://postgres:postgres@127.0.0.1:54322/postgres`). Ajuste o SQL para bater com o existente.

- [ ] **Step 2: Teste pgTAP** em `supabase/tests/database/ui_redesign_test.sql`, seguindo o padrão de `core_test.sql` (dois usuários, `set local role authenticated`, `request.jwt.claims`): (a) usuário B não vê `notices`/`user_settings` de A; (b) B não consegue `update` em notice de A (0 linhas); (c) `insert into user_settings(theme) values ('neon')` falha com `check_violation`; (d) `insert into alexa_commands(kind) values ('delete_device')` funciona. Rode `npx supabase migration up --local && npx supabase test db` → PASS.

- [ ] **Step 3: Testes de domínio (falhando)**

```dart
// app/test/domain/notice_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/notice.dart';
void main() {
  final now = DateTime(2026, 10, 11, 12);
  test('activeNotices tira arquivados e expirados e ordena fixado > alta > recente', () {
    final list = activeNotices([
      Notice(id: 'velho', title: 'a', createdAt: DateTime(2026, 10, 1)),
      Notice(id: 'novo', title: 'b', createdAt: DateTime(2026, 10, 10)),
      Notice(id: 'alta', title: 'c', priority: NoticePriority.alta, createdAt: DateTime(2026, 9, 1)),
      Notice(id: 'fixo', title: 'd', pinned: true, createdAt: DateTime(2026, 8, 1)),
      Notice(id: 'exp', title: 'e', expiresAt: DateTime(2026, 10, 10)),
      Notice(id: 'arq', title: 'f', archivedAt: DateTime(2026, 10, 9)),
    ], now);
    expect(list.map((n) => n.id), ['fixo', 'alta', 'novo', 'velho']);
  });
  test('expira exatamente agora conta como expirado', () {
    expect(activeNotices([Notice(id: 'x', title: 'x', expiresAt: now)], now), isEmpty);
  });
  test('toMap/fromMap ida e volta', () {
    final n = Notice(id: 'i', title: 't', body: 'b', priority: NoticePriority.alta, pinned: true,
        expiresAt: DateTime.utc(2026, 10, 12).toLocal());
    final back = Notice.fromMap({...n.toMap(), 'created_at': '2026-10-11T00:00:00Z'});
    expect([back.title, back.body, back.priority, back.pinned, back.expiresAt],
        [n.title, n.body, n.priority, n.pinned, n.expiresAt]);
  });
}
```
```dart
// app/test/domain/user_settings_test.dart
test('tema desconhecido ou ausente vira violeta', () {
  expect(UserSettings.fromMap({'theme': 'neon'}).theme, 'violeta');
  expect(UserSettings.fromMap({}).theme, 'violeta');
  expect(UserSettings.fromMap({'theme': 'coral', 'hidden_alexa_devices': ['a']}).hiddenAlexaDevices, ['a']);
});
```
```dart
// app/test/domain/system_notices_test.dart (now = sábado 2026-10-10 22:00)
// 1) 2 tarefas com dueAt antes de hoje e não feitas -> SystemNotice(id:'overdue', text:'2 tarefas atrasadas', route:'/tarefas')
// 2) 1 tarefa atrasada -> '1 tarefa atrasada'
// 3) WakePlan ativo days [7] (domingo) 06:30 label 'Aula' -> id 'wake-<planId>', text 'Despertar “Aula” amanhã às 06:30', route '/casa'
// 4) WakePlan desativado -> nenhum aviso de despertar
// 5) bridge offline (lastSeen 1h atrás) com plano ativo -> id 'bridge', text == bridgeWarning(...)
```
Escreva os 5 casos acima como `test(...)` reais com `TaskItem`, `WakePlan` e `BridgeStatus` construídos explicitamente.
```dart
// acrescentar em agenda_test.dart
test('resolveEventEnd joga o fim para o dia seguinte se for antes do início', () {
  final start = DateTime(2026, 10, 10, 22);
  expect(resolveEventEnd(start, DateTime(2026, 10, 10), 2, 0), DateTime(2026, 10, 11, 2));
  expect(resolveEventEnd(start, DateTime(2026, 10, 10), 23, 0), DateTime(2026, 10, 10, 23));
  expect(resolveEventEnd(start, DateTime(2026, 10, 12), 1, 0), DateTime(2026, 10, 12, 1));
});
test('evento 22:00→02:00 aparece nos dois dias', () {
  final e = CalendarEvent(id: 'f', title: 'Festa', startsAt: DateTime(2026, 10, 10, 22), endsAt: DateTime(2026, 10, 11, 2));
  expect(eventsOnDay([e], DateTime(2026, 10, 10)), [e]);
  expect(eventsOnDay([e], DateTime(2026, 10, 11)), [e]);
  expect(eventsOnDay([e], DateTime(2026, 10, 12)), isEmpty);
});
// acrescentar em models_test.dart
test('moved define e limpa completedAt', () {
  final now = DateTime(2026, 10, 11, 9);
  final t = TaskItem(id: 't', title: 'x');
  final done = t.moved(TaskStatus.done, now);
  expect([done.status, done.completedAt], [TaskStatus.done, now]);
  final back = done.moved(TaskStatus.todo, now);
  expect([back.status, back.completedAt], [TaskStatus.todo, null]);
  expect(t.moved(TaskStatus.doing, now).completedAt, isNull);
});
```

- [ ] **Step 4: Rode e veja falhar** (`flutter test test/domain`) → erros de símbolo inexistente.

- [ ] **Step 5: Implemente**

```dart
// domain/agenda.dart (+)
DateTime resolveEventEnd(DateTime start, DateTime endDay, int endHour, int endMinute) {
  var end = DateTime(endDay.year, endDay.month, endDay.day, endHour, endMinute);
  final sameDay = endDay.year == start.year && endDay.month == start.month && endDay.day == start.day;
  if (sameDay && !end.isAfter(start)) end = DateTime(end.year, end.month, end.day + 1, endHour, endMinute);
  return end;
}
// domain/task_item.dart (método de TaskItem)
TaskItem moved(TaskStatus to, DateTime now) => TaskItem(
      id: id, title: title, description: description, status: to, dueAt: dueAt,
      completedAt: to == TaskStatus.done ? (status == TaskStatus.done ? completedAt : now) : null,
      spaceId: spaceId, noteId: noteId, source: source, externalId: externalId);
// domain/notice.dart
List<Notice> activeNotices(Iterable<Notice> notices, DateTime now) {
  final list = notices.where((n) => n.archivedAt == null && (n.expiresAt == null || n.expiresAt!.isAfter(now))).toList();
  final epoch = DateTime(0);
  list.sort((a, b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    if (a.priority != b.priority) return a.priority == NoticePriority.alta ? -1 : 1;
    return (b.createdAt ?? epoch).compareTo(a.createdAt ?? epoch);
  });
  return list;
}
```
`Notice.toMap` grava `priority` como `'normal'|'alta'`, datas com `encodeDate`; `fromMap` usa `parseDate`, prioridade desconhecida → normal. `UserSettings.toMap` = `{'theme': theme, 'hidden_alexa_devices': hiddenAlexaDevices}`; `fromMap` valida contra `themeIds`. `systemNotices` usa `groupTasks(tasks, now)[TaskGroup.atrasadas]`, `bridgeWarning(bridge, wakePlans, now)` e, para cada plano ativo, o próximo disparo `DateTime(…hour, minute)` em hoje ou amanhã cujo `weekday` ∈ `days` e que esteja em `(now, now+24h]`; texto "hoje"/"amanhã" + `HH:MM` com `twoDigits`.

- [ ] **Step 6: Repositórios**
  - `Repository` + `watchNotices/upsertNotice/deleteNotice`. `MemoryRepository`: mapa `_notices`, ordem `createdAt` desc, respeita `failWrites`. `SupabaseRepository`: `_watch('notices', Notice.fromMap, 'created_at')`, `_upsert('notices', ...)`, `_delete`.
  - `MemorySettingsRepository({UserSettings initial = const UserSettings(), this.failWrites = false})` com stream que emite o valor atual e cada `saveSettings`.
  - `SupabaseSettingsRepository(SupabaseClient db)`: `watchSettings` = `db.from('user_settings').stream(primaryKey: ['user_id']).map((rows) => rows.isEmpty ? const UserSettings() : UserSettings.fromMap(rows.first))`; `saveSettings` = `upsert({...s.toMap(), 'user_id': db.auth.currentUser!.id})`, erros viram `RepositoryException` (mesmo `_guard` do `SupabaseAlexaRepository`).
  - Testes de memória: `memory_settings_repository_test.dart` (emite padrão, emite após salvar, `failWrites` lança `RepositoryException`) e notices em `memory_repository_test.dart` (upsert/delete/stream).

- [ ] **Step 7: Providers e wiring** — em `providers.dart`: `settingsRepositoryProvider` (throw), `settingsProvider = StreamProvider<UserSettings>((ref) => ref.watch(settingsRepositoryProvider).watchSettings())`, `noticesProvider = StreamProvider<List<Notice>>((ref) => ref.watch(repositoryProvider).watchNotices())`. `main.dart`: override com `SupabaseSettingsRepository(client)`. `test/helpers.dart`: parâmetro `SettingsRepository? settings` → override `settings ?? MemorySettingsRepository()`.

- [ ] **Step 8: Verifique**: `flutter analyze` limpo; `flutter test --exclude-tags integration` todo verde (as telas ainda são as antigas).

---

### Task 2: Tema (10 sistemas), fontes, shell, Ajustes, árvore de notas

**Depende de:** Task 1 (`settingsProvider`, `settingsRepositoryProvider`, `UserSettings`, `themeIds`).

**Files:**
- Create: `app/tool/gen_themes.dart` (script Dart que lê `../docs/superpowers/specs/assets/themes-10.json` e escreve `lib/ui/themes.dart`), `app/lib/ui/themes.dart` (gerado, commitado)
- Create: `app/lib/ui/org_theme.dart` (`OrgTokens` + `buildOrgTheme`), `app/lib/ui/motif_painter.dart`, `app/lib/ui/org_widgets.dart` (`OrgCard`, `OrgBadge`, `PageHeader`, reescrever `SectionHeader`/`EmptyHint` em cima dos tokens — mova-os de `common.dart` mantendo os mesmos nomes exportados)
- Create: `app/lib/features/settings/settings_screen.dart`, `app/lib/features/more/more_screen.dart`, `app/lib/features/notes/notes_tree.dart`
- Create: `app/assets/google_fonts/` com `Sora-Regular.ttf`, `Sora-SemiBold.ttf`, `Sora-Bold.ttf`, `FiraCode-Regular.ttf`, `FiraCode-Medium.ttf`, `Inter-Regular.ttf`, `Inter-SemiBold.ttf`, `Inter-Bold.ttf` + os `OFL.txt` das licenças
- Modify: `app/pubspec.yaml` (`google_fonts`, assets), `app/lib/app/app.dart`, `app/lib/app/shell.dart`, `app/lib/app/router.dart`, `app/lib/app/providers.dart` (`googleFontsEnabledProvider`), `app/test/helpers.dart` (desliga google fonts nos testes), `app/test/flutter_test_config.dart` (`GoogleFonts.config.allowRuntimeFetching = false`)
- Delete: `app/lib/app/theme.dart`
- Test: `app/test/ui/org_theme_test.dart`, `app/test/app/shell_test.dart` (atualizar), `app/test/features/settings_test.dart`, `app/test/features/notes_tree_test.dart`

**Interfaces — Produces:**
```dart
// ui/themes.dart (gerado)
class OrgThemeSpec { final String id, name, tagline, display, sans, mono, glyph, motif;
  final double radiusSm, radiusMd, radiusLg;
  final Color surface, surfaceRaised, line, ink, inkMuted, accent, accentDeep, onAccent, accentText, accentSoft, secondary, secondarySoft; }
const List<OrgThemeSpec> orgThemes; // 10, na ordem de themeIds
OrgThemeSpec orgThemeById(String id); // desconhecido -> violeta
// ui/org_theme.dart
class OrgTokens extends ThemeExtension<OrgTokens> { final OrgThemeSpec spec; ... }
extension OrgTokensX on BuildContext { OrgThemeSpec get org; } // Theme.of(this).extension<OrgTokens>()!.spec
ThemeData buildOrgTheme(OrgThemeSpec spec, {bool googleFonts = true});
// ui/motif_painter.dart
class MotifPainter extends CustomPainter { MotifPainter({required this.motif, required this.color}); }
class MotifBackground extends StatelessWidget { const MotifBackground({super.key, required this.child, this.height = 140}); }
// ui/org_widgets.dart
class OrgCard extends StatelessWidget { const OrgCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap}); }
class OrgBadge extends StatelessWidget { const OrgBadge(this.label, {super.key, this.tone = OrgBadgeTone.accent}); }
enum OrgBadgeTone { accent, secondary, neutral, danger }
class PageHeader extends StatelessWidget { const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []}); }
// rotas
'/ajustes' -> SettingsScreen; '/mais' -> MoreScreen; '/notas' -> (Task 7 cria NotesScreen; nesta task aponte '/notas' para SpacesScreen)
// notes_tree.dart
class NotesTree extends ConsumerStatefulWidget { const NotesTree({super.key, this.onOpen}); } // busca + espaços expansíveis + notas + "Sem espaço" + botão nova nota
```

- [ ] **Step 1: Gerador de temas.** `tool/gen_themes.dart` lê o JSON (chaves `tokens[<nome>][0]` = escuro, `fonts`, `radius`, `glyph`, `motif`, `name`, `tagline`) e escreve `lib/ui/themes.dart` com `const orgThemes = [...]` na ordem `violeta, safira, musgo, lunar, indigo, grafite, coral, cobalto, cacto, bronze` e o nome exibido com acento (`Índigo` para `indigo`). Rode `dart run tool/gen_themes.dart` e confira que `themes.dart` contém `Color(0xFF160F1E)` (surface Violeta) e `Color(0xFFB8692F)` (accent Bronze).

- [ ] **Step 2: Teste do tema (falhando)**
```dart
// test/ui/org_theme_test.dart
test('10 temas, ids na ordem, desconhecido vira violeta', () {
  expect(orgThemes.map((t) => t.id), themeIds);
  expect(orgThemeById('neon').id, 'violeta');
});
test('mapeamento Material segue as regras dos PDFs', () {
  for (final s in orgThemes) {
    final t = buildOrgTheme(s, googleFonts: false);
    expect(t.brightness, Brightness.dark);
    expect(t.colorScheme.primary, s.accentDeep);
    expect(t.colorScheme.onPrimary, s.onAccent);
    expect(t.colorScheme.surface, s.surface);
    expect(t.colorScheme.onSurface, s.ink);
    expect(t.colorScheme.onPrimaryContainer, s.accentText);
    expect(t.extension<OrgTokens>()!.spec.id, s.id);
  }
});
```
- [ ] **Step 3: `buildOrgTheme`** — `ColorScheme(brightness: dark, primary: accentDeep, onPrimary: onAccent, primaryContainer: accentSoft, onPrimaryContainer: accentText, secondary: secondary, onSecondary: surface, secondaryContainer: secondarySoft, onSecondaryContainer: ink, tertiary: accent, onTertiary: surface, error: Color(0xFFF2726B), onError: Color(0xFF1A0000), surface: surface, onSurface: ink, onSurfaceVariant: inkMuted, outline: line, outlineVariant: line, surfaceContainerLowest..Highest: interpolações de surface→surfaceRaised)`. `scaffoldBackgroundColor: surface`; `cardTheme` (surfaceRaised, borda `line`, `radiusMd`); `inputDecorationTheme` (filled surfaceRaised, borda `line`, foco `accentText`); `navigationRailTheme`/`navigationBarTheme` (indicador `accentSoft`, ícone/label selecionado `accentText`); `textTheme`: se `googleFonts`, `GoogleFonts.getTextTheme(sans, base)` com headlines/títulos via `GoogleFonts.getFont(display)`; senão o `Typography.material2021().white` padrão; cor de texto `ink`; `textSelectionTheme` (cursor `accentText`). `extensions: [OrgTokens(spec)]`. Rode o teste → PASS.
- [ ] **Step 4: Fontes embutidas.** Baixe os TTF estáticos do Google Fonts (`https://fonts.google.com/download?family=Sora` etc., ou do repositório `github.com/google/fonts` — pastas `ofl/sora`, `ofl/firacode`, `ofl/inter`; gere instâncias estáticas se só houver variável, ou use os estáticos de `static/`) para `assets/google_fonts/` com os nomes exatos listados em Files (convenção do pacote `google_fonts`: `Familia-Peso.ttf`). Declare `assets: - assets/google_fonts/` no pubspec. Inclua os `OFL.txt`.
- [ ] **Step 5: App e provider.** `providers.dart`: `final googleFontsEnabledProvider = Provider<bool>((ref) => true);`. `app.dart` vira `ConsumerWidget`: lê `settingsProvider.value?.theme ?? 'violeta'`, `theme: buildOrgTheme(orgThemeById(id), googleFonts: ref.watch(googleFontsEnabledProvider))`, `themeMode: ThemeMode.dark`, `darkTheme` igual. `helpers.dart`: override `googleFontsEnabledProvider` → false. `flutter_test_config.dart`: `GoogleFonts.config.allowRuntimeFetching = false;`.
- [ ] **Step 6: Shell novo.** `AppShell` (≥720px): barra lateral própria (não `NavigationRail`) com largura 248 e botão recolher (fica 64, só ícones), cabeçalho `glyph + 'Organizacional'` em fonte display; itens: Início `/`, Agenda `/agenda`, Tarefas `/tarefas`, Notas `/notas` (expande `NotesTree` abaixo quando a barra está aberta), Notícias `/noticias`, Casa `/casa`, Ajustes `/ajustes`; item ativo com fundo `accentSoft` e texto `accentText`, raio `radiusSm`. Celular: `NavigationBar` com Início, Agenda, Tarefas, Notas, Mais (`/mais`). Mantenha `Key`s: `ValueKey('nav-<path>')` em cada item (ex.: `nav-/agenda`) e `Key('sidebar-collapse')`. Atualize `test/app/shell_test.dart`: desktop mostra os 7 itens e a árvore; celular mostra 5 destinos; tocar "Mais" abre `/mais` com Notícias, Casa e Ajustes; recolher esconde os rótulos.
- [ ] **Step 7: NotesTree.** Campo de busca `Key('notes-search')` filtra por título (sem acento/caixa — reutilize `normalizeTitle` de `wikilinks.dart`); cada espaço é um `ExpansionTile` (`ValueKey('tree-space-<id>')`) com suas notas (`ValueKey('tree-note-<id>')`, toque → `context.push('/nota/<id>')`); notas sem espaço em "Sem espaço"; botão `Key('tree-new-note')` cria `Note(id: newId(), title: 'Sem título N')` (N = próximo livre) e abre. Teste em `notes_tree_test.dart`: busca "calc" mostra "Cálculo — Resumo" e esconde "Redes"; toque abre a nota.
- [ ] **Step 8: Ajustes.** `SettingsScreen`: `PageHeader('Ajustes')`; seção "Tema" com `Wrap` de 10 cartões (`ValueKey('theme-<id>')`), cada um pintado com o próprio `surface/surfaceRaised/accent`, glifo, nome e tagline curta (texto antes do "—"); selecionado com borda `accentText` 2px e ícone ✓. Toque → `settingsRepositoryProvider.saveSettings(current.copyWith(theme: id))`; erro → `showError('Não foi possível salvar o tema.')`. Seção "Conta": e-mail (`Supabase` não é acessível em teste — receba via novo `currentEmailProvider = Provider<String?>((ref) => null)` sobrescrito no `main.dart` com `client.auth.currentUser?.email`) e botão `Key('sign-out')` (`signOutProvider`). Teste: tocar `theme-coral` salva `'coral'` no `MemorySettingsRepository` e o `Theme.of` passa a ter `primary == orgThemeById('coral').accentDeep`.
- [ ] **Step 9: MoreScreen** (`/mais`): lista com Notícias, Casa, Ajustes (ícones + `context.go`).
- [ ] **Step 10: Motivo.** `MotifPainter` desenha os 10 motivos com `color` (= `accent` com alpha 0.10–0.18): `diagonal-stripes` (linhas 135° a cada 9px), `wiregrid` (grade 12px), `leaf-rings`/`orbit-rings` (círculos concêntricos no canto direito), `ornament-dots`/`dot-grid` (pontos 14px/10px), `scanlines` (linhas horizontais 4px), `wave-lines` (arcos concêntricos do canto inferior esquerdo), `brick-texture` (tijolos 16×8), `cross-hatch` (±45° a cada 7px). `MotifBackground` = `Stack(CustomPaint(MotifPainter(...)) atrás de child)` com `ClipRRect(radiusLg)`. Teste de fumaça: cada motivo pinta sem exceção num `Canvas` de 200×100 (`PictureRecorder`).
- [ ] **Step 11: Rotas**: adicionar `/ajustes`, `/mais`, `/notas` (→ `SpacesScreen` por enquanto). Remover `lib/app/theme.dart`. `flutter analyze` limpo e `flutter test --exclude-tags integration` verde — testes antigos que dependiam de cores/estrutura do shell devem ser ajustados para o novo shell, sem remover o que eles verificam de comportamento.

---

### Task 3: Ponte — comando `delete_device` (paralela à Task 1)

**Files:**
- Modify: `bridge/src/commands.ts`, `bridge/src/gateway.ts`, `bridge/src/alexa-remote-gateway.ts`, `bridge/src/main.ts` (passa a ressincronizar após `delete_device`), `bridge/test/fake-gateway.ts`, `bridge/test/commands.test.ts`, `bridge/test/mappers.test.ts`
- Create (se o mapeador não estiver em arquivo próprio): função exportada `findApplianceId(raw: unknown, entityId: string): string | null` junto de `mapSmartEntities` (procure com `grep -rn mapSmartEntities bridge/src`)

**Interfaces:** `CommandKind` += `'delete_device'`; `AlexaGateway.deleteSmartDevice(entityId: string): Promise<void>`; `CommandDeps` inalterado (`executeCommand` chama `deps.gateway.deleteSmartDevice` e depois `deps.sync()`). Payload do app: `{ entityId: string }`.

- [ ] **Step 1: Testes falhando** (`commands.test.ts`):
```ts
it('delete_device apaga no gateway e ressincroniza', async () => {
  const gateway = new FakeGateway();
  const sync = vi.fn(async () => {});
  const r = await executeCommand({ id: '1', kind: 'delete_device', payload: { entityId: 'ent-1' }, createdAt: new Date() },
    { gateway, sync, wakeTest: async () => 'ok' });
  expect(r).toBe('ok');
  expect(gateway.deleted).toEqual(['ent-1']);
  expect(sync).toHaveBeenCalledOnce();
});
it('delete_device sem entityId falha com CommandError', async () => {
  await expect(executeCommand({ id: '1', kind: 'delete_device', payload: {}, createdAt: new Date() },
    { gateway: new FakeGateway(), sync: async () => {}, wakeTest: async () => 'ok' })).rejects.toThrow('campo "entityId" ausente');
});
```
E em `mappers.test.ts`:
```ts
it('findApplianceId acha o applianceId pelo entityId em getSmarthomeDevices', () => {
  const raw = { locationDetails: { Default_Location: { amazonBridgeDetails: { amazonBridgeDetails: {
    'LambdaBridge_x': { applianceDetails: { applianceDetails: {
      'SKILL_abc': { applianceId: 'SKILL_abc', entityId: 'ent-1', friendlyName: 'Luz' } } } } } } } } };
  expect(findApplianceId(raw, 'ent-1')).toBe('SKILL_abc');
  expect(findApplianceId(raw, 'nao-existe')).toBeNull();
});
```
- [ ] **Step 2: Implementação.** `findApplianceId` percorre recursivamente objetos e devolve `applianceId` do primeiro objeto com `entityId === alvo` (robusto ao formato aninhado). `AlexaRemoteGateway.deleteSmartDevice`: `const raw = await this.call('getSmarthomeDevices')`; `const id = findApplianceId(raw, entityId)`; se `null` → `throw new Error('dispositivo não encontrado na Alexa')`; senão `await this.call('deleteSmarthomeDevice', id)`. `FakeGateway`: `deleted: string[]` e `deleteSmartDevice` faz push. `executeCommand`: `case 'delete_device': await deps.gateway.deleteSmartDevice(str(p, 'entityId')); await deps.sync(); return 'ok';`.
- [ ] **Step 3:** `npx vitest run` e `npx tsc -p tsconfig.typecheck.json --noEmit` verdes.

---

## Onda 2 (Tasks 4–8 em paralelo; cada uma só mexe nos próprios arquivos + seus testes)

Todas consomem da Onda 1: `context.org` (`OrgThemeSpec`), `OrgCard`, `OrgBadge`, `OrgBadgeTone`, `PageHeader`, `SectionHeader`, `EmptyHint`, `MotifBackground`, providers `settingsProvider`, `settingsRepositoryProvider`, `noticesProvider`, `repositoryProvider`, `clockProvider`, domínio de Task 1.

### Task 4: Início com quadro de avisos

**Files:** Modify `app/lib/features/today/today_screen.dart`; Create `app/lib/features/today/notice_board.dart`, `app/lib/features/today/notice_dialog.dart`; Test `app/test/features/today_test.dart` (atualizar) e `app/test/features/notice_board_test.dart`.

- [ ] **Step 1: Testes (falhando)** em `notice_board_test.dart` com `pumpApp(location: '/')`:
  - repo com notice fixado "Prova de Cálculo" e notice expirado "Velho" → mostra "Prova de Cálculo", não mostra "Velho".
  - tarefa atrasada no repo → mostra "1 tarefa atrasada" com `OrgBadge('sistema')`; tocar leva a `/tarefas`.
  - `Key('new-notice')` → diálogo (`Key('notice-title')`, `Key('notice-body')`, switch `Key('notice-pinned')`, prioridade `Key('notice-priority-alta')`, data de expiração opcional) → "Salvar" grava no repo e aparece.
  - menu do aviso → "Arquivar" (`ValueKey('archive-notice-<id>')`) define `archivedAt` e some; "Editar" reabre o diálogo preenchido.
  - `failWrites = true` ao salvar → diálogo continua aberto com o texto e mostra "Não foi possível salvar o aviso."
- [ ] **Step 2: Implementação.** `TodayScreen`: `MotifBackground` com saudação ("Bom dia/Boa tarde/Boa noite" por hora) em fonte display e data por extenso; depois `NoticeBoard` (cartão "Quadro de avisos": `systemNotices(...)` primeiro, cada um com ícone de alerta, cor `inkMuted`, `OrgBadge('sistema', tone: neutral)`, toque → `context.go(route)`; depois `activeNotices(...)` com glifo do tema, título, corpo em 2 linhas, `OrgBadge('alta', tone: danger)` se alta, ícone de alfinete se fixado, menu ⋮ Editar/Fixar-Desafixar/Arquivar/Excluir); seções "Hoje" (eventos do dia — reaproveite `buildDayAgenda`) e "Tarefas" (atrasadas + hoje com checkbox que usa `moved`), e manchetes (comportamento atual de notícias em Hoje). Remova o banner antigo da ponte desta tela (agora é aviso do sistema). Preserve o comportamento existente coberto em `today_test.dart` (virada da meia-noite etc.), ajustando apenas seletores visuais.
- [ ] **Step 3:** `flutter test test/features/today_test.dart test/features/notice_board_test.dart` verde; `flutter analyze` limpo.

### Task 5: Kanban de tarefas

**Files:** Modify `app/lib/features/tasks/tasks_screen.dart`; Create `app/lib/features/tasks/kanban_board.dart`, `app/lib/features/tasks/task_card.dart`, `app/lib/features/tasks/task_dialog.dart`; Modify/Test `app/test/features/tasks_test.dart`, `app/lib/ui/task_tile.dart` (se continuar usado pela Home, só restyle).

- [ ] **Step 1: Testes (falhando)**:
  - desktop (1000×800): três colunas `ValueKey('column-todo')`, `column-doing`, `column-done` com contagens; arrastar `ValueKey('task-card-a')` até `column-done` (use `tester.timedDrag` / `startGesture` + `moveTo` + `up`) → no repo `status == done` e `completedAt == now`; arrastar de volta para `column-todo` → `completedAt == null`.
  - celular (400×800): `TabBar` com "A fazer 2", "Fazendo 0", "Feito 0"; long-press no cartão → bottom sheet "Mover para…" com "Fazendo" → muda para aba correta e grava.
  - `Key('quick-add-todo')` (e `-doing`, `-done`) cria tarefa já no status da coluna; texto só espaços não cria; `failWrites` mantém o texto e mostra erro (mesmo comportamento dos testes atuais de `quick-add`).
  - filtro por espaço (chips) continua funcionando.
  - tocar no cartão abre `TaskDialog` (título, descrição, prazo, espaço, excluir) e salvar atualiza.
- [ ] **Step 2: Implementação.** `KanbanBoard` recebe `tasks`, `spaces`, `onMove(TaskItem, TaskStatus)`, `onOpen(TaskItem)`, `onQuickAdd(String, TaskStatus)`; desktop = `Row` de 3 `DragTarget<TaskItem>` com `LongPressDraggable` no mobile e `Draggable` no desktop; coluna destacada (`accentSoft`) quando um cartão passa por cima. `TaskCard`: título, `OrgBadge(espaço)`, prazo (vermelho/`danger` se atrasado ou ≤ 1 dia, formato "amanhã", "sex, 16"), ícone de nota se `noteId`; em "Feito" com opacidade 0.55 e riscado. Ordenação dentro da coluna: prazo asc (sem prazo no fim), depois título; "Feito" por `completedAt` desc, limitado a 20 com "Ver mais". `onMove` chama `repo.upsertTask(task.moved(status, now))` e mostra erro em falha.
- [ ] **Step 3:** testes de tarefas verdes; analyze limpo.

### Task 6: Agenda em calendário + diálogo de evento

**Files:** Modify `app/lib/features/agenda/agenda_screen.dart`, `app/lib/features/agenda/event_dialog.dart`; Create `app/lib/features/agenda/week_view.dart`, `month_view.dart`, `mobile_calendar.dart`, `calendar_layout.dart` (cálculo puro de posições); Test `app/test/features/agenda_test.dart` (atualizar), `app/test/features/calendar_layout_test.dart`, `app/test/features/event_dialog_test.dart`.

- [ ] **Step 1: Testes puros (falhando)** em `calendar_layout_test.dart`:
```dart
// layoutDay(events, day) -> List<PlacedEvent{event, top (min desde 00:00), height (min), column, columns}>
test('evento 22:00→02:00 fica 22:00–24:00 no dia 1 e 00:00–02:00 no dia 2', () {
  final e = CalendarEvent(id: 'f', title: 'Festa', startsAt: DateTime(2026,10,10,22), endsAt: DateTime(2026,10,11,2));
  final d1 = layoutDay([e], DateTime(2026,10,10)).single;
  expect([d1.top, d1.height], [22*60, 120]);
  final d2 = layoutDay([e], DateTime(2026,10,11)).single;
  expect([d2.top, d2.height], [0, 120]);
});
test('eventos sobrepostos dividem a largura em colunas', () {
  final a = CalendarEvent(id: 'a', title: 'A', startsAt: DateTime(2026,10,12,8), endsAt: DateTime(2026,10,12,10));
  final b = CalendarEvent(id: 'b', title: 'B', startsAt: DateTime(2026,10,12,9), endsAt: DateTime(2026,10,12,11));
  final p = layoutDay([a, b], DateTime(2026,10,12));
  expect(p.map((x) => (x.column, x.columns)), [(0, 2), (1, 2)]);
});
test('altura mínima de 20 min para eventos curtos', () { /* 08:00–08:05 -> height 20 */ });
```
- [ ] **Step 2: Testes de widget (falhando)**:
  - desktop abre na **semana** atual (`Key('view-week')` selecionado), cabeçalho "5 – 11 out 2026" para `now = 2026-10-10`; `Key('next-week')`/`prev-week` navegam; `Key('view-month')` mostra a grade do mês com eventos como pílulas; tocar num dia do mês volta para a semana desse dia.
  - tocar num horário vazio da semana (`ValueKey('slot-2026-10-12-14')`) abre `EventDialog` com início 14:00 e fim 15:00 no dia 12.
  - `EventDialog`: escolher início 22:00 e fim 02:00 no mesmo dia mostra "Termina no dia seguinte" e salva `endsAt = dia+1 02:00`; fim igual ao início continua bloqueado pela mensagem de `validateEventTimes`; campo `Key('event-end-day')` permite escolher outro dia de término.
  - tocar num evento abre o diálogo em modo edição (título preenchido, botão `ValueKey('delete-event-<id>')`), salvar atualiza o mesmo id.
  - celular (400×800): mês compacto com ponto nos dias com evento; tocar no dia lista os eventos daquele dia ("22:00 → dom 02:00" para o evento que atravessa); `Key('new-event')` presente.
- [ ] **Step 3: Implementação.** `calendar_layout.dart` puro (`layoutDay`, `PlacedEvent`, `monthGrid(DateTime month) -> List<DateTime>` de 6×7 começando na segunda). `WeekView`: cabeçalho de dias (hoje em `accentText`), coluna de horas 00–23 com 48px/h, rolagem inicial em 07:00, eventos com cor = `accentDeep` (ou `secondary` se `spaceId` par — mantenha simples: cor por hash do `spaceId` entre `accentDeep`, `secondary`, `accent`), texto `onAccent`; tocar/arrastar verticalmente em área vazia cria seleção e abre o diálogo com o intervalo arredondado a 15 min. `MonthView`: grade 6×7, até 3 pílulas + "+N". `MobileCalendar`: mês compacto + lista do dia. `AgendaScreen`: `PageHeader` com botões Semana|Mês (só desktop), ‹ › e "Hoje", FAB/`Key('new-event')`. Use `eventsFromProvider` com `from` = início do intervalo visível. `EventDialog(initialStart, initialEnd, spaces, existing?)`: data de início, hora de início, data de término (padrão = início), hora de término, espaço, local opcional; ao salvar usa `resolveEventEnd`; mostra o aviso "Termina no dia seguinte" quando aplicável; edição preserva `id`, `source`, `externalId`.
- [ ] **Step 4:** testes da agenda verdes; analyze limpo.

### Task 7: Editor de notas WYSIWYG (appflowy_editor) + tela Notas

**Files:** Modify `app/pubspec.yaml` (`appflowy_editor`), `app/lib/features/notes/note_screen.dart`; Create `app/lib/features/notes/markdown_bridge.dart`, `app/lib/features/notes/rich_note_editor.dart`, `app/lib/features/notes/notes_screen.dart`; Modify `app/lib/app/router.dart` **somente** a linha da rota `/notas` (→ `NotesScreen`); restyle `app/lib/features/spaces/space_screen.dart` e `spaces_screen.dart`; Test `app/test/features/markdown_bridge_test.dart`, `app/test/features/notes_test.dart` (atualizar), `app/test/features/spaces_test.dart` (atualizar).

- [ ] **Step 1: Compatibilidade.** `flutter pub add appflowy_editor` e `flutter analyze`. Se não resolver com Flutter 3.47 (conflito de versão ou erro de compilação em `flutter build linux --debug`), tente a versão do Git (`git: https://github.com/AppFlowy-IO/appflowy-editor.git`, ref `main`); se ainda falhar, **pare e reporte** ao coordenador com o erro (não troque de biblioteca por conta própria).
- [ ] **Step 2: Testes de ida e volta (falhando)** em `markdown_bridge_test.dart`:
```dart
const corpus = [
  '# Título\n\nTexto com **negrito** e _itálico_.',
  '- [ ] tarefa aberta\n- [x] tarefa feita',
  '- item 1\n- item 2\n\n1. um\n2. dois',
  '> citação',
  'Veja [[Cálculo — Resumo]] e [[Redes]].',
  '```\ncódigo\n```',
  '[site](https://example.com)',
];
for (final md in corpus) {
  test('ida e volta: ${md.split('\n').first}', () {
    expect(documentToNoteMarkdown(noteMarkdownToDocument(md)), md);
  });
}
test('link wiki vira href wiki: no documento', () {
  final doc = noteMarkdownToDocument('Veja [[Redes]].');
  expect(jsonEncode(doc.toJson()), contains('wiki:Redes'));
});
```
  Se algum caso do corpus não sobreviver por limitação do encoder do appflowy (ex.: `_itálico_` sair como `*itálico*`), **normalize** em `documentToNoteMarkdown` para a forma usada no corpus; se for impossível, documente no teste com a forma canônica que o editor produz e garanta que é **estável** (`f(f(x)) == f(x)`).
- [ ] **Step 3: Implementação.** `markdown_bridge.dart`: `Document noteMarkdownToDocument(String md)` = `markdownToDocument(wikiToLinks(md))` onde `[[X]]` → `[X](wiki:<X url-encoded>)`; `String documentToNoteMarkdown(Document d)` = `linksToWiki(documentToMarkdown(d))` revertendo `[X](wiki:X)` → `[[X]]` e normalizando fim de linha. `RichNoteEditor(initialMarkdown, onChanged(String md), onWikiLink(String title))`: `EditorState(document: noteMarkdownToDocument(...))`, `AppFlowyEditor` com estilo vindo do tema (fonte `sans`, cor `ink`, links `accentText`, cursor `accentText`), menu `/` (slash) e toolbar flutuante padrões; escuta `editorState.transactionStream` e chama `onChanged(documentToNoteMarkdown(editorState.document))`; clique em link com href `wiki:` chama `onWikiLink`.
- [ ] **Step 4: NoteScreen.** Mantém **toda** a lógica de salvamento existente (`_debounce`, `_flush`, rascunhos, `_remoteNotice`, exclusão, criação por wikilink) — o editor rico só substitui o `TextField` do corpo: `onChanged: (md) { _body.text = md; _changed(); }`. Não chame `_changed` na construção do editor (abrir a nota não pode gravar). Botão `Key('toggle-markdown')` ("Ver como Markdown") alterna para o `TextField` `Key('note-body')` existente; ao voltar, recria o `EditorState` a partir de `_body.text`. Atualização remota sem edições locais recria o `EditorState`. Título em fonte display grande. Backlinks "Mencionada em" mantidos.
- [ ] **Step 5: Testes de tela** (`notes_test.dart`): os testes atuais que usam `note-body` passam a ativar antes `toggle-markdown`; novo teste: abrir uma nota e sair sem editar **não** chama `upsertNote` (conte chamadas via um `MemoryRepository` instrumentado ou compare `updatedAt`); novo teste: digitar no editor rico (`tester.enterText` não funciona no AppFlowy — use `editorState` exposto por `Key('rich-editor')` → `tester.widget<RichNoteEditor>` e dispare `onChanged('novo')`) grava após o debounce.
- [ ] **Step 6: NotesScreen** (`/notas`): no celular mostra `NotesTree` em tela cheia; no desktop mostra a lista de espaços (restyle de `SpacesScreen` com `OrgCard`s por tipo de espaço) — a árvore já está na barra lateral. Restyle de `SpaceScreen` (cabeçalho com nome/tipo, notas e tarefas do espaço como `OrgCard`s). Testes de espaços verdes.

### Task 8: Casa — ocultar e remover dispositivos

**Files:** Modify `app/lib/features/home/home_screen.dart`, `app/lib/features/home/wake_plan_screen.dart` (restyle); Test `app/test/features/home_test.dart`.

- [ ] **Step 1: Testes (falhando)**:
  - menu do dispositivo `ValueKey('device-menu-<id>')` → "Ocultar do app" grava `hiddenAlexaDevices` contendo o id no `MemorySettingsRepository` e o dispositivo some; seção `Key('hidden-devices')` "Ocultos (1)" → "Mostrar" remove da lista.
  - dispositivo `kind: 'smart'` → "Remover da Alexa" abre confirmação com o texto "Isso apaga “<nome>” da sua conta Amazon. Não dá para desfazer pelo app."; confirmar envia comando `delete_device` com `{'entityId': id}` (verifique `MemoryAlexaRepository.sent`) e mostra o resultado ("Feito."); cancelar não envia nada.
  - Echo (`kind: 'echo'`) não tem "Remover da Alexa", só "Ocultar do app"; Echo oculto some também dos chips "Tocar em".
  - falha ao salvar ajustes → "Não foi possível ocultar o dispositivo." e o dispositivo continua visível.
- [ ] **Step 2: Implementação** com `settingsProvider`/`settingsRepositoryProvider`; restyle com `PageHeader('Casa')`, `OrgCard` por seção, `MotifBackground` no topo; manter todas as `Key`s existentes da tela.
- [ ] **Step 3:** `home_test.dart` verde; analyze limpo.

---

## Onda 3 — Integração e entrega (coordenador)

### Task 9: Verificação completa, deploy e push

- [ ] **Step 1:** `flutter analyze` sem issues; `TZ=America/Sao_Paulo flutter test --exclude-tags integration` todo verde; `npx supabase test db` verde; bridge `npx vitest run` + typecheck verdes.
- [ ] **Step 2:** Revisão de código do branch inteiro (subagente revisor) contra o spec; corrigir achados.
- [ ] **Step 3:** Rodar o app (`flutter run -d linux`) e conferir visualmente Início, Agenda (semana/mês, evento 22:00→02:00), Tarefas (arrastar), Notas (editor), Ajustes (trocar 3 temas), Casa.
- [ ] **Step 4:** Commit por onda já feito; `npx supabase db push --linked` (migração nova); imagem da ponte (`docker build` → `docker save | ssh … docker load` → `docker compose up -d bridge`) na VM `198.51.100.10`; build Linux release instalado em `~/.local/opt/organizacional`; APKs (`--split-per-abi` arm64 + completo) em `~/organizacional-builds/`; `git push origin HEAD:main`.
