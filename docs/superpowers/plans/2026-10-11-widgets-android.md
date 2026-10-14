# Widgets Android — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Widgets de tela inicial (Hoje, Tarefas, Próxima prova) para o app Flutter Organizacional, atualizados em segundo plano.

**Architecture:** Dart monta um resumo JSON (contrato do spec) e o grava via `home_widget`; widgets Kotlin (`HomeWidgetProvider`) leem e desenham com RemoteViews; `workmanager` roda a cada 30 min um isolate que busca no Supabase e regrava o resumo.

**Tech Stack:** Flutter 3.47.5 (`~/development/flutter/bin`), home_widget ^0.10.0 e workmanager ^0.10.10 (já no pubspec), supabase_flutter, Kotlin/Android (AGP do projeto), RemoteViews.

**Spec:** `docs/superpowers/specs/2026-10-11-widgets-android-design.md` — **contém o contrato de dados** (chaves, JSON, regras de exibição). Leia inteiro antes de começar; é a única interface entre as Tasks 1 e 2.

## Global Constraints

- Textos de interface em **pt-BR**. Só Android (guarde chamadas de plugin com `!kIsWeb && Platform.isAndroid`).
- Cores nos widgets só via tema do contrato (`w_theme`), nenhuma cor fixa exceto o fallback do tema Violeta quando `w_theme` faltar.
- Contrato do spec é imutável: se precisar mudar algo, pare e reporte ao coordenador.
- Subagentes **não fazem `git commit`**. Task 1 (Dart) **não roda builds Android**; só Task 2 roda `flutter build apk --debug` (evita disputa pelo Gradle).
- Testes: `cd app && TZ=America/Sao_Paulo ~/development/flutter/bin/flutter test --exclude-tags integration`; `flutter analyze` limpo. `export PATH="$HOME/development/flutter/bin:$PATH"`.

## Review Focus

1. Evento 22:00→02:00 aparece hoje **e** amanhã, com texto "→" correto (Task 1 testa o resumo; Task 2 trata no Kotlin).
2. Sem sessão (login expirado) o widget mostra "Abra o app e entre" em vez de lista vazia enganosa (Task 1 `signed_out`; Task 2 renderiza).
3. Fuso/virada do dia: o widget calcula "hoje/amanhã/em N dias" pelo calendário local do aparelho, não por divisão de 24 h (Task 2).
4. Falha de rede no segundo plano mantém o último resumo bom (Task 1: `error` não apaga `w_events`/`w_tasks`).
5. Título com aspas, quebra de linha ou emoji não quebra o JSON nem o layout (Task 1 teste de ida e volta; Task 2 `maxLines`/ellipsize).

---

### Task 1: Dart — resumo, sincronização, segundo plano e links

**Files:**
- Create: `app/lib/widgets/widget_snapshot.dart`, `widget_sink.dart`, `widget_sync.dart`, `widget_background.dart`, `widget_links.dart`
- Modify: `app/lib/main.dart` (registro do `workmanager`, ligação dos links, override do `WidgetSink`), `app/lib/app/providers.dart` (`widgetSinkProvider`, só se necessário)
- Test: `app/test/widgets/widget_snapshot_test.dart`, `widget_links_test.dart`, `widget_sync_test.dart`

**Interfaces — Produces:** exatamente as do spec ("Dart"): `buildWidgetSnapshot`, `WidgetSink`/`HomeWidgetSink`/`NoopWidgetSink`, `routeForWidgetUri`, `callbackDispatcher`. Nomes dos 3 providers nativos para `HomeWidget.updateWidget(qualifiedAndroidName: 'dev.organizacional.organizacional.widgets.<Nome>')`: `HojeWidgetProvider`, `TarefasWidgetProvider`, `ProvaWidgetProvider` (Task 2 cria).

- [x] **Step 1: Testes do resumo (falhando)** em `widget_snapshot_test.dart`, `TZ=America/Sao_Paulo`, `now = DateTime(2026, 10, 11, 12)`:
  - chaves presentes: `w_state`, `w_generated_at`, `w_theme`, `w_events`, `w_tasks`; `w_theme` tem as 10 cores `#RRGGBB` do tema pedido (`violeta` → surface `#160F1E`); `themeId` desconhecido → violeta.
  - eventos: inclui os de ontem 00:00 até hoje+14 dias, ordenados; exclui antes de ontem e depois de +14 d; `kind` = `prova` para "Prova 2 — M02 D" e "NP3 — C03 E", `aula` para "M02", `outro` para "Reunião NP" e "Estudo - C03"; evento 22:00→02:00 (`start`/`end` em epoch millis corretos); `allDay` e `location` (null quando vazio).
  - tarefas: só não concluídas; `doing` antes de `todo`; dentro do status por `due` crescente, sem prazo por último; limite 30; `due` em epoch millis ou null.
  - título com `"`, `\n`, emoji e `\\` sobrevive a `jsonDecode(snapshot['w_events'])`.
  - `state: 'signed_out'` → `w_events`/`w_tasks` = `"[]"` e `w_state = "signed_out"`; `state: 'error'` não é gerado por esta função (o chamador mantém dados antigos): a função só aceita `ok|signed_out` — `error` é gravado pelo background como `save({'w_state': 'error'})` sem tocar nas outras chaves.
- [x] **Step 2:** rode e veja falhar. **Step 3:** implemente `widget_snapshot.dart` (use `jsonEncode`; cores a partir de `orgThemeById(id)` em `lib/ui/themes.dart`: `surface, surfaceRaised, line, ink, inkMuted, accentDeep, onAccent, accentText, accentSoft`; `danger` = `#F2726B`). **Step 4:** testes verdes.
- [x] **Step 5: Links.** `routeForWidgetUri`: `organizacional://agenda` → `/agenda`, `organizacional://tarefas` → `/tarefas`, qualquer outro host/esquema → `null`; testes. Em `main.dart`, no Android: `HomeWidget.initiallyLaunchedFromHomeWidget().then(handle)` e `HomeWidget.widgetClicked.listen(handle)`, com `handle(Uri?)` chamando `router.go(route)` quando `routeForWidgetUri` não for null.
- [x] **Step 6: Sink e sincronização em primeiro plano.** `HomeWidgetSink.save` chama `HomeWidget.saveWidgetData<String>` para cada par e `refresh()` chama `HomeWidget.updateWidget(qualifiedAndroidName: …)` para os 3 providers. `widget_sync.dart`: `widgetSyncProvider` (Provider que assina `eventsFromProvider`/`tasksProvider`/`settingsProvider`, com debounce de 2 s e usando `clockProvider`) chama `buildWidgetSnapshot` + `sink.save` + `sink.refresh`; o `widgetSinkProvider` padrão é `NoopWidgetSink` (testes) e `main.dart` o sobrescreve com `HomeWidgetSink` só no Android. Teste `widget_sync_test.dart` com um sink falso: inserir uma tarefa no `MemoryRepository` faz o sink receber um `w_tasks` com ela (use `fakeAsync`/`pump` para o debounce). O provider deve ser lido em algum lugar sempre ativo (ex.: `ref.watch(widgetSyncProvider)` no `build` de `OrganizacionalApp`, que já é `ConsumerWidget`).
- [x] **Step 7: Segundo plano.** `widget_background.dart` conforme o spec. `callbackDispatcher` anotado com `@pragma('vm:entry-point')`; dentro: `WidgetsFlutterBinding.ensureInitialized()`, `Supabase.initialize(url: String.fromEnvironment('SUPABASE_URL'), publishableKey: String.fromEnvironment('SUPABASE_ANON_KEY'))` (reaproveite as mesmas constantes de `main.dart`; se `Supabase` já estiver inicializado, use a instância), `client.auth.currentSession == null` → `signed_out`. Separe a parte testável em `Future<Map<String,String>> fetchSnapshot(SupabaseClient/consultas injetáveis, DateTime now)` (consultas atrás de uma pequena interface `WidgetDataSource { Future<List<CalendarEvent>> events(DateTime from, DateTime to); Future<List<TaskItem>> openTasks(); Future<String> themeId(); }` com `SupabaseWidgetDataSource` real e uma versão falsa nos testes; teste: dados → resumo `ok`; fonte lançando exceção → resultado indica `error` e **não** sobrescreve eventos/tarefas). Em `main.dart` (Android): `Workmanager().initialize(callbackDispatcher)` e `registerPeriodicTask('widgets-refresh', 'widgetsRefresh', frequency: const Duration(minutes: 30), constraints: Constraints(networkType: NetworkType.connected), existingWorkPolicy: ExistingPeriodicWorkPolicy.update)`.
- [x] **Step 8:** `flutter analyze` limpo; `flutter test` completo verde (nada fora de `lib/widgets`, `main.dart` e `test/widgets` deve mudar).

### Task 2: Android nativo — providers, layouts e manifest

**Files:** (todos sob `app/android/app/src/main/`)
- Create: `kotlin/dev/organizacional/organizacional/widgets/{WidgetData.kt,HojeWidgetProvider.kt,TarefasWidgetProvider.kt,ProvaWidgetProvider.kt}`
- Create: `res/layout/{widget_hoje.xml,widget_tarefas.xml,widget_prova.xml}`, `res/xml/{widget_hoje_info.xml,widget_tarefas_info.xml,widget_prova_info.xml}`, `res/drawable/widget_bg.xml`, `res/values/widget_strings.xml`
- Modify: `AndroidManifest.xml` (3 `<receiver>`), `app/android/app/build.gradle.kts` só se algo for estritamente necessário
- Test: `app/android/app/src/test/kotlin/dev/organizacional/organizacional/widgets/WidgetDataTest.kt` **somente se** o projeto já tiver `testImplementation` configurado ou for trivial adicionar (JUnit 4 + `org.json:json:20240303` para testar o parse fora do aparelho); caso contrário, deixe a lógica de formatação em funções puras de `WidgetData.kt` bem pequenas e documente no relatório.

**Interfaces — Consumes:** o contrato do spec (chaves `w_*`, JSON, regras de exibição). **Produces:** classes `dev.organizacional.organizacional.widgets.HojeWidgetProvider`, `TarefasWidgetProvider`, `ProvaWidgetProvider` (nomes usados pela Task 1).

- [x] **Step 1:** leia a fonte do `home_widget` Android (`~/.pub-cache/hosted/pub.dev/home_widget-*/android/src/main/kotlin/es/antonborri/home_widget/`: `HomeWidgetProvider`, `HomeWidgetLaunchIntent`) para usar a API real da versão instalada.
- [x] **Step 2: `WidgetData.kt`:** `data class` para tema/evento/tarefa; `parseTheme/parseEvents/parseTasks(prefs: SharedPreferences)` com `org.json`, tolerantes a ausência/lixo (retornam vazio/tema Violeta `#160F1E / #251E2D / #413B49 / #EFE9F7 / #9B8FAE / #6633CC / #FFFFFF / #C0A9FF / #291B41 / #F2726B`); funções puras `eventsToday(events, nowMillis, zone)`, `dayLabel(dueMillis, nowMillis, zone)` ("hoje"/"amanhã"/"dd/MM"), `daysUntil(startMillis, nowMillis, zone)` (diferença de dias de **calendário**, `java.time`), `isStale(generatedAt, nowMillis)`; `parseColor` com fallback.
- [x] **Step 3: Layouts.** Raiz `FrameLayout` com `ImageView` de fundo `@drawable/widget_bg` (retângulo arredondado 20dp, `android:tint` não — pinte por código com `setInt(R.id.bg, "setColorFilter", cor)`), conteúdo em `LinearLayout` com `padding` 12dp; título pequeno em caixa-alta; `widget_hoje`: 5 linhas (`TextView` `time` + `TextView` `title`, `maxLines=1`, `ellipsize=end`), linha "+N" e `empty`; `widget_tarefas`: 6 linhas + "+N" + `empty`; `widget_prova`: título grande, "quando", local, `empty`. Ids previsíveis (`row1_time`, `row1_title`, … ). Tudo só com views suportadas por RemoteViews.
- [x] **Step 4: Providers.** Cada um estende `HomeWidgetProvider`, em `onUpdate(context, appWidgetManager, appWidgetIds, widgetData)` lê o contrato, monta `RemoteViews`, define textos/cores (`setTextColor`, `setViewVisibility` para linhas não usadas) e `setOnClickPendingIntent(R.id.root, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("organizacional://agenda" | "organizacional://tarefas")))`; Prova abre `organizacional://agenda`. Estados: `signed_out` → "Abra o app e entre"; vazio → textos do spec; "desatualizado" pequeno quando `isStale` e `w_state=="error"`. Use `Clock`/`System.currentTimeMillis()` e `ZoneId.systemDefault()` na hora de desenhar (virada do dia correta sem rede).
- [x] **Step 5: Infos e manifest.** `res/xml/*_info.xml`: `initialLayout`, `minWidth/minHeight` (Hoje 250×110dp, Tarefas 180×180dp, Prova 110×110dp), `targetCellWidth/Height` (4×2, 3×3, 2×2), `resizeMode="horizontal|vertical"`, `updatePeriodMillis="1800000"`, `description` e `label` pt-BR em `widget_strings.xml` ("Organizacional · Hoje", "Organizacional · Tarefas", "Organizacional · Próxima prova"). `AndroidManifest.xml`: 3 `<receiver android:exported="true">` com `intent-filter` `android.appwidget.action.APPWIDGET_UPDATE` e `<meta-data android:name="android.appwidget.provider" android:resource="@xml/…"/>`.
- [x] **Step 6: Build.** `cd app && flutter build apk --debug --dart-define-from-file=env.json` (o arquivo `env.json` existe e é ignorado pelo git) deve compilar; se aparecer erro de `compileSdk` em plugin novo, o projeto já tem o ajuste em `android/build.gradle.kts` (não o remova). Confira com `aapt`/`unzip -l` que o APK contém as 3 classes (`classes*.dex` não é legível; basta o build verde + `grep` do manifest mesclado em `build/app/intermediates/merged_manifests/debug*/AndroidManifest.xml` mostrando os 3 receivers).
- [x] **Step 7:** relatório com a lista de arquivos, o resultado do build, e qualquer ponto do contrato que não deu para cumprir.

---

### Task 3 (coordenador): Integração

- [x] Rodar `flutter analyze` + suíte completa + `flutter build apk --release` (arm64, ofuscado, como antes); revisar o diff; commit e `git push origin HEAD:main`; enviar o APK ao usuário e explicar como adicionar os widgets (toque longo na tela inicial → Widgets → Organizacional).
