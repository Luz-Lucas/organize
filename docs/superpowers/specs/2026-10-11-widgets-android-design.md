# Widgets Android (Hoje, Tarefas, Próxima prova) — Design

**Data:** 2026-10-11 · Aprovado pelo usuário no chat. **Só Android.** iOS fora do escopo.

## Decisões

| Tema | Decisão |
|---|---|
| Widgets | **Hoje** (4×2, redimensionável), **Tarefas** (3×3), **Próxima prova** (2×2). |
| Atualização | Em segundo plano a cada **30 min** (`workmanager`) buscando no Supabase com a sessão salva; com o app aberto, atualiza a cada mudança. Virada do dia e contagem regressiva calculadas **no widget**, sem rede (`updatePeriodMillis` 30 min redesenha a partir do que está guardado). |
| Visual | Cores do tema escolhido (1 dos 10), enviadas no resumo. Fonte do sistema (RemoteViews não usa fonte do app). |
| Ponte | `home_widget` (SharedPreferences privado do app) + 3 `HomeWidgetProvider` em Kotlin. Listas com linhas fixas (sem `RemoteViewsService`). |
| Cliques | Abrem o app na tela certa via URI `organizacional://agenda` / `organizacional://tarefas`. |
| Fora do escopo | Marcar tarefa/criar evento pelo widget; opção de ocultar títulos; iOS. |

## Contrato de dados (Dart escreve → Kotlin lê)

Chaves de `HomeWidget.saveWidgetData<String>` (todas **String**). Horários em **epoch millis (UTC)**; cores em `#RRGGBB`.

- `w_state`: `"ok"` | `"signed_out"` | `"error"`.
- `w_generated_at`: epoch millis (string) de quando o resumo foi gerado.
- `w_theme`: JSON `{"surface","surfaceRaised","line","ink","inkMuted","accentDeep","onAccent","accentText","accentSoft","danger"}` (todos `#RRGGBB`; `danger` = `#F2726B`).
- `w_events`: JSON array, ordenado por `start`, janela de ontem 00:00 a hoje+14 dias. Item: `{"id":str,"title":str,"start":int,"end":int,"allDay":bool,"location":str|null,"kind":"aula"|"prova"|"outro"}`. `kind="prova"` quando o título casa `^(prova|np\d)` (sem diferenciar maiúsculas); `kind="aula"` quando o título é só um código de turma (`^[A-Z]\d{2}$`, ex. `M02`); senão `outro`.
- `w_tasks`: JSON array só de tarefas **não concluídas** (máx. 30), `doing` primeiro, depois por `due` crescente (sem prazo por último). Item: `{"id":str,"title":str,"status":"todo"|"doing","due":int|null}`.

Regras de exibição no widget (Kotlin, usando o relógio e o fuso do aparelho):
- **Hoje:** eventos cujo intervalo toca o dia de hoje (`start < fimDoDia && end > inicioDoDia`), até 5 linhas ("HH:mm título"; evento que atravessa a meia-noite mostra "HH:mm → dia seguinte"; dia inteiro mostra "Dia todo"); em andamento = texto em `accentText`; já terminado = `inkMuted`; "+N" quando houver mais; vazio → "Nada na agenda hoje".
- **Tarefas:** até 6 linhas; prazo como "hoje", "amanhã" ou "dd/MM"; atrasada (prazo antes do início de hoje) em `danger`; "+N" quando houver mais; vazio → "Nenhuma tarefa".
- **Próxima prova:** primeiro evento `kind="prova"` com `end > agora`; linhas: título, "hoje às HH:mm" / "amanhã às HH:mm" / "em N dias" (N = diferença de dias de calendário), local; nenhuma → "Sem provas à vista".
- `w_state="signed_out"` → todos mostram "Abra o app e entre"; `"error"` com resumo antigo → mostra o resumo e "desatualizado" pequeno se `agora - generated_at > 3 h`.

## Dart

- `lib/widgets/widget_snapshot.dart` (puro, testado): `Map<String, String> buildWidgetSnapshot({required DateTime now, required Iterable<CalendarEvent> events, required Iterable<TaskItem> tasks, required String themeId, String state = 'ok'})` → as chaves acima.
- `lib/widgets/widget_sink.dart`: `abstract interface class WidgetSink { Future<void> save(Map<String,String> data); Future<void> refresh(); }` + `HomeWidgetSink` (usa `HomeWidget.saveWidgetData` e `updateWidget` para os 3 providers) + `NoopWidgetSink`.
- `lib/widgets/widget_sync.dart`: provider que, com o app aberto, escuta eventos/tarefas/ajustes e grava o resumo (debounce 2 s), só no Android.
- `lib/widgets/widget_background.dart`: `callbackDispatcher` (`@pragma('vm:entry-point')`) do `workmanager`: inicializa Supabase, restaura a sessão, busca `events` (ends_at ≥ ontem, starts_at ≤ hoje+14d), `tasks` (status ≠ done) e `user_settings.theme`, monta o resumo e grava; sem sessão → `signed_out`; exceção → mantém o último resumo e marca `error`. Registro: `Workmanager().registerPeriodicTask('widgets-refresh', 'widgetsRefresh', frequency: 30 min, constraints: connected, existingWorkPolicy: update)` em `main.dart` (só Android).
- `lib/widgets/widget_links.dart`: `String? routeForWidgetUri(Uri)` (`organizacional://agenda` → `/agenda`, `organizacional://tarefas` → `/tarefas`, outro → `null`) + ligação no `main.dart`/router: `HomeWidget.initiallyLaunchedFromHomeWidget()` e `HomeWidget.widgetClicked`.

## Android (Kotlin, pacote `dev.organizacional.organizacional`)

`android/app/src/main/kotlin/dev/organizacional/organizacional/widgets/`: `WidgetData.kt` (leitura/parse do contrato, tema, formatadores), `HojeWidgetProvider.kt`, `TarefasWidgetProvider.kt`, `ProvaWidgetProvider.kt` (estendem `HomeWidgetProvider`). Layouts em `res/layout/`, infos em `res/xml/`, drawable `widget_bg.xml` (retângulo arredondado branco, pintado com `setColorFilter` na cor `surface`/`surfaceRaised`), `res/values/strings.xml` (rótulos em pt-BR). Receivers no `AndroidManifest.xml`. Toque → `HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("organizacional://agenda"))`.

## Testes e verificação

Testes de unidade do resumo (inclui evento que atravessa a meia-noite, ordenação de tarefas, `kind`, estado) e do `routeForWidgetUri`; `flutter analyze` limpo; `flutter build apk --debug` compila com os widgets; suíte completa verde. Aparência final: conferida no celular pelo usuário (não há aparelho/emulador aqui).
