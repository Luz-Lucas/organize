# Widgets Calendário e Lista de mercado — Plano

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:test-driven-development. Sem commit.

**Goal:** dois widgets Android novos, do mesmo tamanho do "Agenda e Tarefas" (4×4, `minWidth/minHeight 250dp`,
`targetCell 4×4`, redimensionável), para empilhar (stack) na tela inicial.

**Design aprovado pelo usuário (2026-10-20):**
- **Calendário:** em cima, grade do mês (cabeçalho "outubro 2026" com setas ‹ ›, iniciais seg…dom, 6×7 dias; hoje destacado;
  dia escolhido marcado; pontinho na cor da etiqueta — ou cor de destaque se sem etiqueta — nos dias com eventos; dias de
  outros meses esmaecidos). Embaixo, os eventos do dia escolhido (horário + título com ponto da etiqueta; "Dia livre" se
  vazio; "+N" se não couber). Ao abrir/atualizar, o dia escolhido é hoje (se o dia virar, volta para hoje).
  Tocar num dia **troca a lista sem abrir o app**; setas trocam o mês (limitado à janela de dados); tocar num evento ou no
  cabeçalho da lista abre a Agenda (`URI_AGENDA`). Mostra todos os eventos (inclusive academia).
- **Lista de mercado:** título "Mercado · N itens" (nome da primeira lista por `position`); itens pendentes
  (não marcados) agrupados por seção na ordem da lista (`section_order` ou padrão), com quantidade; "Lista vazia" se nada.
  **Tocar num item marca como comprado** (some do widget na hora; grava no Supabase); tocar no título abre Compras
  (`organizacional://compras` ou o esquema de URI que `widget_links.dart`/`main.dart` usam).
- Mesmos tema, transparência (`w_bg_alpha`), estado `signed_out`/`error` e atualização dos widgets atuais.

## Arquitetura
- **Dados (Dart → SharedPreferences via home_widget)**, em `app/lib/widgets/widget_snapshot.dart` + `widget_sync.dart` +
  `widget_background.dart`: novas chaves
  - `w_cal_events`: eventos de `[início do mês anterior, fim do mês seguinte]` (compacto: id, title, start, end, allDay, tagColor);
    `w_cal_range`: `{from, to}` em millis (as setas não passam disso).
  - `w_shop`: `{listId, listName, sections: [{name, label, items: [{id, name, quantity}]}]}` da primeira lista.
  - `widget_sync.dart` passa a ouvir também eventos da janela do calendário e os providers de compras
    (`shoppingListsProvider`, `shoppingItemsProvider`); `widget_background.dart` (workmanager) busca os mesmos dados.
  - Registrar os dois providers novos na lista de widgets atualizados (`widget_sink.dart`).
- **Kotlin** (`app/android/app/src/main/kotlin/dev/organizacional/organizacional/widgets/`): `CalendarioWidgetProvider` e
  `MercadoWidgetProvider` (herdam `BaseOrgWidget`), layouts `res/layout/widget_calendario.xml`/`widget_mercado.xml`,
  infos `res/xml/widget_calendario_info.xml`/`widget_mercado_info.xml` (copiar dimensões de `widget_agenda_tarefas_info.xml`),
  strings de descrição, `AndroidManifest.xml` (receivers; o do calendário também recebe as ações próprias abaixo).
  - Calendário: ações `…CAL_PREV`, `…CAL_NEXT`, `…CAL_PICK` (extra: data `yyyy-MM-dd`) tratadas no `onReceive` do provider:
    guarda mês exibido e dia escolhido por `appWidgetId` nas prefs do widget e redesenha (sem abrir o app).
    Lógica pura (montar as 42 células, eventos do dia, cores) em `WidgetData`/arquivo novo testável com JUnit.
  - Mercado: tocar num item → remove o item do `w_shop` local na hora (redesenha) e dispara a gravação em segundo plano
    via `HomeWidgetBackgroundIntent` do home_widget (`HomeWidget.registerInteractivityCallback`, callback Dart top-level
    `@pragma('vm:entry-point')` que inicializa o Supabase como `widget_background.dart` faz e executa
    `update shopping_items set checked = true where id = …`). Se falhar, a próxima sincronização restaura o item.
    Lista com até ~12 linhas visíveis conforme a altura (como `AgendaTarefasWidgetProvider` faz com `heightDp`); "+N".
- Abrir Compras pelo widget: tratar a URI nova no `handle` de `main.dart` (`HomeWidget.widgetClicked`) → `/compras`.

## Review Focus
1. Mês com 6 semanas e mês começando no domingo (grade seg…dom) — células certas.
2. Evento que atravessa a meia-noite ou de dia inteiro com vários dias → aparece em todos os dias que toca.
3. Dia virou com o widget aberto num dia antigo → volta para hoje no próximo redesenho do dia.
4. Tocar item sem sessão/sem rede → o item volta na próxima sincronização; nada trava.
5. Sem lista nenhuma ainda (usuário nunca abriu Compras) → "Lista vazia", sem erro.

## Verificação
- Dart: testes de `buildWidgetSnapshot` para as chaves novas e do callback (com fakes); `cd app && TZ=America/Sao_Paulo flutter test test/widgets -j 2`,
  depois a suíte inteira UMA vez (`--exclude-tags integration -j 2`) e `flutter analyze` limpo.
- Kotlin: JUnit em `app/android/app/src/test/kotlin/.../widgets/` para a grade e o parse (`cd app/android && ./gradlew testDebugUnitTest`).
- Compilação: `cd app && flutter build apk --debug` UMA vez no fim. Depois mate o Gradle com `pkill -f '[G]radleDaemon'` (com os colchetes,
  para não matar o próprio shell). Pouca RAM: nada em paralelo.
