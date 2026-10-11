# Widget "Agenda e Tarefas" + ícone do app que segue o tema — Design e Plano

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development ou executing-plans. Steps com checkbox.

**Aprovado no chat (2026-10-12).** Base: `docs/superpowers/specs/2026-10-11-widgets-android-design.md` (contrato de dados `w_*`, regras de exibição, providers existentes) — leia antes.

## Decisões

- **Widget 4º (`AgendaTarefasWidgetProvider`, 4×4):** duas seções empilhadas — "Eventos de hoje" (até 4 linhas: horário + título; em andamento destacado em `accentText`, terminado esmaecido, "+N") e "Tarefas" (até 4 linhas: título + prazo; atrasada em `danger`; "doing" antes de "todo", "+N"). Cada seção abre sua tela: eventos → `organizacional://agenda`, tarefas → `organizacional://tarefas`. Usa os **mesmos dados** (`w_events`, `w_tasks`, `w_theme`, `w_state`) e as mesmas regras de exibição dos widgets Hoje e Tarefas (reaproveite `WidgetData.kt` e `BaseOrgWidget.kt`; não duplique lógica). `signed_out` → "Abra o app e entre". Altura baixa → menos linhas (como os outros). Label: "Organizacional · Agenda e Tarefas".
- **Ícone por tema (Android):** 10 `activity-alias` (um por tema: `violeta, safira, musgo, lunar, indigo, grafite, coral, cobalto, cacto, bronze`), cada um com um **ícone adaptativo** nas cores do tema; o app liga o alias do tema escolhido e desliga os outros (`PackageManager.setComponentEnabledSetting(..., DONT_KILL_APP)`, ligando o novo **antes** de desligar os outros, nunca ficando sem nenhum). Padrão: `violeta` habilitado. `minSdk` do app passa a **26** (ícone adaptativo; o celular do usuário é bem mais novo). Ícone: fundo = `surface` do tema; no centro um cartão arredondado em `accentDeep` com um "check" em `onAccent` e uma faixa superior fina (cabeçalho de calendário) em `accentText`; camada `monochrome` com a mesma silhueta. Cores de `docs/superpowers/specs/assets/themes-10.json` (índice `tokens[<nome>][0]` = escuro).
- **Dart:** `AppIconService` (interface: `Future<String?> current()`, `Future<void> set(String themeId)`), `NoopAppIconService` (padrão, testes/outras plataformas), `MethodChannelAppIconService` no canal `dev.organizacional/app_icon` (só Android). Um provider observa `settingsProvider`: quando o tema muda (e uma vez ao iniciar), se `current() != tema`, chama `set(tema)`; erros são ignorados (nunca quebram o app). Em **Ajustes → Tema**, uma nota (só Android): "O ícone do app muda junto com o tema. Se o atalho da tela inicial sumir, arraste o ícone novo da lista de apps."
- Linux: ícone fixo (fora do escopo).

## Constraints

- pt-BR; cores só de tokens/tema (exceto os arquivos gerados dos ícones, que vêm do JSON de temas). `export PATH="$HOME/development/flutter/bin:$PATH"`; `cd app && flutter analyze` limpo e `TZ=America/Sao_Paulo flutter test --exclude-tags integration` verde ao final.
- **Só a Task 2 roda Gradle/Android builds** (`export JAVA_HOME=~/development/android-studio/jbr ANDROID_HOME=~/Android/Sdk`; `flutter build apk --debug --dart-define-from-file=env.json`). A Task 1 **não** roda builds.
- **`AndroidManifest.xml` é editado pelas duas tasks:** use edições pequenas ancoradas (Edit), releia o arquivo imediatamente antes de editar e nunca reescreva o arquivo inteiro. Task 1 só acrescenta um `<receiver>`; Task 2 só mexe no filtro LAUNCHER da `MainActivity` e acrescenta os `<activity-alias>`.
- Sem `git commit`/`stash` pelos subagentes; não tocar em `mcp/`, `bridge/`, `supabase/`, nuvem ou VM.

---

### Task 1: Widget Agenda e Tarefas

**Files:** (sob `app/android/app/src/main/`) Create: `kotlin/dev/organizacional/organizacional/widgets/AgendaTarefasWidgetProvider.kt`, `res/layout/widget_agenda_tarefas.xml`, `res/xml/widget_agenda_tarefas_info.xml`; Modify: `res/values/widget_strings.xml`, `AndroidManifest.xml` (+1 receiver), `app/lib/widgets/widget_sink.dart` (acrescentar o nome do provider em `widgetProviderNames`), `app/test/widgets/widget_sink_test.dart` (se existir; senão um teste simples de que a lista tem 4 nomes terminando em `AgendaTarefasWidgetProvider`); testes JUnit em `app/android/app/src/test/kotlin/.../widgets/` somente se criar helper puro novo.

- [ ] Leia os 3 providers existentes, `BaseOrgWidget.kt`, `WidgetData.kt` e os layouts atuais; reaproveite ids/estilos/helper de desenho.
- [ ] Implemente provider + layout + info (`minWidth/minHeight` 250×250dp, `targetCellWidth/Height` 4×4, `resizeMode="horizontal|vertical"`, `updatePeriodMillis=1800000`) + string + receiver. Duas áreas clicáveis com `PendingIntent` distintos (`HomeWidgetLaunchIntent`, requestCodes diferentes dos outros widgets).
- [ ] Dart: registrar o novo nome em `widgetProviderNames`; `flutter analyze` e `flutter test test/widgets` verdes.
- [ ] Relatório: arquivos, como as duas áreas clicáveis foram distinguidas, o que o usuário deve conferir no celular.

### Task 2: Ícone por tema

**Files:** Create: `app/tool/gen_app_icons.dart` (gera os recursos a partir do JSON de temas), recursos gerados em `app/android/app/src/main/res/` (`values/ic_launcher_colors.xml` ou colors por tema, `drawable/ic_launcher_fg_<id>.xml`, `mipmap-anydpi-v26/ic_launcher_<id>.xml` com `<background>`, `<foreground>`, `<monochrome>`), `kotlin/dev/organizacional/organizacional/AppIconChannel.kt`; Modify: `MainActivity.kt` (registrar o canal em `configureFlutterEngine`), `AndroidManifest.xml` (remover o `intent-filter` MAIN/LAUNCHER da `MainActivity` e criar os 10 `<activity-alias>`; mantenha o `intent-filter` de deep link se existir), `app/android/app/build.gradle.kts` (`minSdk = maxOf(flutter.minSdkVersion, 26)`), `app/lib/app_icon/app_icon.dart` (+ provider), `app/lib/app/app.dart` (assistir o provider, como `widgetSyncProvider`), `app/lib/main.dart` (override Android), `app/lib/features/settings/settings_screen.dart` (nota); Test: `app/test/app_icon/app_icon_test.dart`, `app/test/android/app_icon_manifest_test.dart`.

- [ ] **Teste do manifesto (falhando):** lê `android/app/src/main/AndroidManifest.xml` e confere: 10 `activity-alias` com nomes `dev.organizacional.organizacional.Icon<Id>` (Id capitalizado) para exatamente os ids de `themeIds`; só o `violeta` com `android:enabled="true"`; cada um com `intent-filter` MAIN + LAUNCHER, `android:exported="true"` e `android:targetActivity=".MainActivity"`; a `MainActivity` **sem** categoria LAUNCHER; e que existe `mipmap-anydpi-v26/ic_launcher_<id>.xml` para cada tema.
- [ ] **Testes Dart (falhando)** com um `AppIconService` falso: mudar o tema de `violeta` para `coral` chama `set('coral')` uma vez; iniciar com `current()=='coral'` e tema `coral` não chama `set`; `set` lançando exceção não derruba o app; `NoopAppIconService` é o padrão em `pumpApp`.
- [ ] Gerador `tool/gen_app_icons.dart` + rodar para criar os recursos (comite os gerados). Kotlin do canal (`current` devolve o id do alias habilitado; `set(id)` habilita o alvo primeiro e depois desabilita os outros, `DONT_KILL_APP`; id inválido → erro `invalid_theme`). Dart conforme "Decisões". Nota nos Ajustes (só quando `defaultTargetPlatform == TargetPlatform.android` e não web).
- [ ] **Build:** `flutter build apk --debug --dart-define-from-file=env.json` verde; confira no manifesto mesclado (`app/build/app/intermediates/merged_manifests/debug*/…/AndroidManifest.xml`) os 10 aliases e a `MainActivity` sem LAUNCHER; com `aapt2 dump badging` do APK (`~/Android/Sdk/build-tools/*/aapt2 dump badging <apk>`) liste `launchable-activity` e confirme que existe exatamente **uma** launchable-activity habilitada por padrão (a do violeta).
- [ ] Relatório: arquivos, decisões de desenho do ícone (inclua um PNG de pré-visualização dos 10 ícones em `/tmp/claude-1000/-home-only-organizacional--claude-worktrees-csharp-pdf-exercises-f0cca4/00000000-0000-4000-8000-000000000000/scratchpad/icones.png`, se conseguir renderizar de forma simples, por exemplo com um script que desenha os retângulos/check com PIL), e o que o usuário deve conferir.

### Task 3 (coordenador)

- [ ] Suíte completa + `flutter analyze`; `flutter build apk --release …` e Linux; commit, push; enviar APK; explicar como adicionar o widget novo e o comportamento do ícone.
