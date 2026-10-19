# Academia, Compras e Início "Para hoje" — Plano

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:test-driven-development. Cada agente faz **só a sua Task** e
> não faz commit (o coordenador commita). Leia `docs/GUIA-DO-DESENVOLVEDOR.md` (seções do app/MCP/ponte) antes.

**Goal:** duas áreas novas (Academia, Compras) e a Início remodelada com "Para hoje".

**Architecture:** Supabase (tabelas novas com RLS e realtime; seção do item decidida no banco) → app Flutter com dois
repositórios novos (interface + Memory + Supabase, padrão de `news_repository.dart`) e telas em `features/fitness` e
`features/shopping` → Início consome os cartões dessas features → MCP e skill da Alexa leem/escrevem as mesmas tabelas.

**Tech Stack:** Flutter 3.47 / Riverpod 3 / go_router; Supabase (Postgres, pgTAP); TypeScript (MCP SDK, ask-sdk-core, vitest).

**Spec:** `docs/superpowers/specs/2026-10-19-academia-compras-inicio-design.md`

## Global Constraints
- Textos em pt-BR; código no estilo do arquivo vizinho (comentários curtos em pt-BR).
- Nada de dado pessoal no repositório (repo público). Nada de nuvem/VM/push: só local.
- Flutter em `~/development/flutter/bin`; testes com `TZ=America/Sao_Paulo flutter test <seus arquivos> -j 2`
  (a máquina tem pouca RAM: **não** rode a suíte inteira; o coordenador roda). `flutter analyze` limpo nos seus arquivos.
- Arquivos compartilhados (`providers.dart`, `router.dart`, `main.dart`, `test/helpers.dart`, `more_screen.dart`,
  `shell.dart`) só a Task 4 edita.
- Seções (ordem padrão, `name` → rótulo): `hortifruti` Hortifrúti, `padaria` Padaria, `acougue` Açougue,
  `frios` Frios e laticínios, `mercearia` Mercearia, `bebidas` Bebidas, `limpeza` Limpeza, `higiene` Higiene,
  `congelados` Congelados, `outros` Outros.
- Evento de academia: título **ou** nome da etiqueta, sem acento e minúsculo, contém `academia`, `treino` ou `musculac`.

## Esquema (Task 1 cria; todas usam) — `supabase/migrations/20261029000000_fitness_shopping.sql`
Todas as tabelas: `id uuid pk default gen_random_uuid()`, `user_id uuid not null default auth.uid() references auth.users on delete cascade`,
RLS com policy "dono" (`user_id = (select auth.uid())`), `revoke all from anon`, na publicação `supabase_realtime`.
Filhas checam no `with check` que o pai é do mesmo dono (como `events.tag_id`).
- `workouts(name text 1..60, position int default 0, created_at timestamptz default now())`
- `workout_exercises(workout_id uuid not null → workouts on delete cascade, name text 1..80, sets int 1..20 default 3,
  reps text 1..20 default '10', load_kg numeric(6,2) null check ≥0, rest_seconds int 0..900 default 90, notes text default '', position int default 0)`
- `workout_sessions(workout_id uuid null → workouts on delete set null, workout_name text 1..60, day date not null,
  started_at timestamptz not null default now(), finished_at timestamptz null)`; índice (user_id, day desc)
- `set_logs(session_id uuid not null → workout_sessions on delete cascade, exercise_id uuid null → workout_exercises on delete set null,
  exercise_name text 1..80, set_index int ≥1, reps int null 0..999, load_kg numeric(6,2) null, done_at timestamptz default now())`;
  único (session_id, exercise_id, set_index); índice (user_id, exercise_id, done_at desc)
- `shopping_lists(name text 1..40, position int default 0, section_order text[] null, created_at …)`; único (user_id, lower(name))
- `shopping_items(list_id uuid not null → shopping_lists on delete cascade, name text 1..80, quantity text default '' (≤30),
  section text null→preenchida, checked bool default false, position int default 0, created_at …)`; `section` com check na lista de seções
- `shopping_frequent(name_key text, name text, section text, times int default 1, last_added_at timestamptz)`; único (user_id, name_key)
- `fold_event_text(t)` já existe (minúsculo sem acento) — reutilize para `name_key`.
- `guess_shopping_section(uid uuid, item text) returns text` (stable, `search_path=''`): seção de `shopping_frequent` para
  `fold(item)`; senão palavras-chave (`like` em `fold(item)`), senão `outros`. Palavras mínimas:
  hortifruti: banana maca tomate alface cebola alho batata cenoura limao laranja fruta verdura legume;
  padaria: pao bolo torrada biscoito bolacha; acougue: carne frango peixe linguica bife costela;
  frios: leite queijo presunto iogurte manteiga requeijao ovo; bebidas: agua suco refrigerante cerveja vinho cafe;
  limpeza: detergente sabao amaciante desinfetante esponja agua sanitaria; higiene: sabonete shampoo xampu
  pasta de dente escova papel higienico desodorante; congelados: sorvete congelad pizza; mercearia: arroz feijao
  macarrao oleo acucar sal farinha molho. (Teste: `leite` → frios, `água sanitária` → limpeza, `Pão francês` → padaria.)
- Gatilhos em `shopping_items`: **before insert** — `section` nula vira `guess_shopping_section(new.user_id, new.name)`;
  **after insert** — upsert em `shopping_frequent` (`times+1`, `name`, `section`, `last_added_at=now()`);
  **after update of section** — atualiza a `section` do frequente com a mesma `name_key` (o app "lembra").
- pgTAP em `supabase/tests/database/fitness_shopping_test.sql`: RLS (outro usuário não vê/insere; não aponta para lista
  /ficha/sessão alheia), palpite de seção (3 casos acima + lembrança após update), frequente conta, cascades.

## Review Focus
1. Lista vazia/primeiro uso: Compras sem nenhuma lista cria "Mercado" sozinha; Academia sem fichas mostra "Criar primeira ficha" (sem quebrar a Início).
2. Item duplicado ("leite" já na lista, não marcado): adicionar de novo não duplica — soma/ignora e avisa "Já está na lista".
3. Ficha editada no meio do treino (exercício apagado): a sessão em andamento continua (logs guardam `exercise_name`).
4. Virada do dia com treino aberto: a sessão é do `day` em que começou; a Início no dia seguinte não mostra o treino de ontem como "em andamento".
5. 360 dp de largura e texto grande: cartões novos e telas sem overflow (`tester.takeException()` nulo).

---

### Task 1: Banco (Onda 1)
**Files:** Create a migração e o pgTAP acima. Verifique: `npx supabase status` (subir com `npx supabase start` se preciso),
`npx supabase migration up --local`, `npx supabase test db` verde (todos os testes, não só o seu). **Não** rode `db push`.

### Task 2: Academia no app (Onda 1)
**Files:** Create `app/lib/domain/workout.dart`, `app/lib/data/fitness_repository.dart` (interface + `MemoryFitnessRepository`),
`app/lib/data/supabase_fitness_repository.dart`, `app/lib/features/fitness/` (`fitness_providers.dart`, `fitness_screen.dart`,
`workout_editor_screen.dart`, `workout_session_screen.dart`, `exercise_history_sheet.dart`, `workout_today_card.dart`);
tests em `app/test/features/fitness/`.

**Interfaces (Produces):**
- Domínio: `Workout{id,name,position,List<WorkoutExercise> exercises}`, `WorkoutExercise{id,workoutId,name,sets,reps(String),loadKg(double?),restSeconds,notes,position}`,
  `WorkoutSession{id,workoutId?,workoutName,day(DateTime date-only),startedAt,finishedAt?,List<SetLog> logs}`,
  `SetLog{id,sessionId,exerciseId?,exerciseName,setIndex,reps(int?),loadKg(double?),doneAt}` — com `fromMap/toMap/copyWith`.
- Puras: `bool isGymEvent(CalendarEvent e, Map<String, EventTag> tags)`; `Workout? nextWorkout(List<Workout> ws, List<WorkoutSession> history)`;
  `SetLog? lastSetFor(String exerciseId, String exerciseName, List<WorkoutSession> history)` (por id, senão por nome);
  `GymToday gymToday({required DateTime now, required Iterable<CalendarEvent> events, required Map<String,EventTag> tags,
  required List<Workout> workouts, required List<WorkoutSession> sessions})` com `sealed GymToday`: `GymNoWorkouts`, `GymRest(Workout? next)`,
  `GymPlanned(Workout w)`, `GymInProgress(WorkoutSession s, int doneSets, int totalSets)`, `GymDone(WorkoutSession s)`.
- `abstract interface class FitnessRepository`: `Stream<List<Workout>> watchWorkouts()`; `Future<void> upsertWorkout(Workout w)`
  (grava a ficha e substitui os exercícios: apaga os que saíram); `Future<void> deleteWorkout(String id)`; `Future<void> reorderWorkouts(List<Workout> ordered)`;
  `Stream<List<WorkoutSession>> watchSessions({required DateTime from})` (com logs); `Future<WorkoutSession> startSession(Workout w, DateTime now)`;
  `Future<void> logSet(SetLog log)` (upsert); `Future<void> deleteSetLog(String id)`; `Future<void> finishSession(String id, DateTime at)`;
  `Future<void> deleteSession(String id)`. Memory com `failWrites` como `MemoryRepository`.
- Providers (em `fitness_providers.dart`): `fitnessRepositoryProvider` (throw sem override), `workoutsProvider`, `recentSessionsProvider`
  (últimos 120 dias), `gymTodayProvider` (usa `clockProvider`, `eventsFromProvider(startOfDay(now))`, `eventTagsProvider`).
- Widgets: `FitnessScreen` (rota `/academia`: fichas + "Hoje" + histórico), `WorkoutTodayCard` (cartão da Início; keys `gym-card`, `gym-start`).
- Testes mínimos: lógica (`nextWorkout` rodízio e volta ao início, `isGymEvent` por título/etiqueta/acento, `gymToday` em cada estado,
  virada do dia — Review Focus 4); tela: criar ficha com 2 exercícios, começar, marcar série com carga pré-preenchida da última vez,
  desmarcar, finalizar; exercício apagado durante o treino (Focus 3); 360 dp (Focus 5).

### Task 3: Compras no app (Onda 1)
**Files:** Create `app/lib/domain/shopping.dart`, `app/lib/data/shopping_repository.dart` (+ `MemoryShoppingRepository`),
`app/lib/data/supabase_shopping_repository.dart`, `app/lib/features/shopping/` (`shopping_providers.dart`, `shopping_screen.dart`,
`shopping_item_sheet.dart`, `shopping_card.dart`); tests em `app/test/features/shopping/`.

**Interfaces (Produces):**
- `enum ShopSection { hortifruti('Hortifrúti'), …, outros('Outros'); final String label; static ShopSection fromName(Object?) }` (ordem = padrão).
- `ShoppingList{id,name,position,List<ShopSection>? sectionOrder}`, `ShoppingItem{id,listId,name,quantity,section,checked,position,createdAt}`,
  `FrequentItem{name,section,times,lastAddedAt}`.
- Puras: `List<(ShopSection, List<ShoppingItem>)> groupBySection(List<ShoppingItem> unchecked, List<ShopSection>? order)`;
  `List<FrequentItem> buyAgain(List<FrequentItem> f, List<ShoppingItem> inList, {int max = 12})` (exclui os que estão na lista não marcados; por `times` desc, depois recente);
  `List<FrequentItem> suggest(String typed, List<FrequentItem> f, {int max = 6})` (prefixo/contém, sem acento).
- `abstract interface class ShoppingRepository`: `Stream<List<ShoppingList>> watchLists()`; `Future<ShoppingList> ensureDefaultList()` ("Mercado" se não houver lista);
  `Future<void> upsertList(ShoppingList l)`; `Future<void> deleteList(String id)`; `Stream<List<ShoppingItem>> watchItems()` (todas as listas);
  `Future<void> addItem({required String listId, required String name, String quantity = '', ShopSection? section})` (seção nula = o banco decide;
  Memory: frequente pelo nome, senão `outros`); `Future<void> updateItem(ShoppingItem i)`; `Future<void> setChecked(String id, bool checked)`;
  `Future<void> deleteItem(String id)`; `Future<int> finishShopping(String listId)` (apaga os marcados, devolve quantos);
  `Stream<List<FrequentItem>> watchFrequent()`.
- Providers: `shoppingRepositoryProvider`, `shoppingListsProvider`, `shoppingItemsProvider`, `frequentItemsProvider`.
- Widgets: `ShoppingScreen` (rota `/compras`, abas/chips por lista, campo de adicionar com sugestões, grupos por seção,
  "No carrinho", "Finalizar compra" com confirmação, editar seção/quantidade, ordem das seções arrastável num diálogo),
  `ShoppingCard` (Início: "Mercado — 7 itens", 3 primeiros, botão Abrir; key `shopping-card`).
- Testes mínimos: lógica das três funções puras; tela: primeira abertura cria Mercado (Focus 1), adicionar com quantidade,
  sugestão ao digitar, duplicado avisa (Focus 2), marcar vai para "No carrinho", finalizar apaga marcados, corrigir seção,
  "Comprar de novo" recoloca, várias listas; 360 dp (Focus 5).

### Task 5: MCP e Alexa (Onda 1)
**Files:** Create `mcp/src/tools/shopping.ts`, `mcp/src/tools/fitness.ts` (registrar em `index.ts`), testes em `mcp/test/`
(siga `tools.test.ts`/`helpers.ts`); modify `bridge/src/skill.ts`, `bridge/src/supabase-store.ts`, `bridge/src/main.ts`,
`bridge/skill/interaction-model.pt-BR.json` (invocationName `organize`), testes em `bridge/test/`.
- MCP: `list_shopping` (listas com itens não marcados e marcados), `add_shopping_items` (`list?` nome, padrão Mercado criado se faltar;
  `items: [{name, quantity?, section?}]` 1..50; ignora o que já está na lista não marcado e diz quais), `update_shopping_item`
  (`id`, `checked?`, `quantity?`, `section?`, `name?`), `remove_shopping_item`, `finish_shopping` (`list?`; DESTRUCTIVE);
  `list_workouts` (fichas com exercícios), `upsert_workout` (`id?`, `name`, `exercises[]` substitui), `list_workout_history`
  (`days?` padrão 30; sessões com séries). Sempre filtrar por `ctx.userId`; seção nula deixa o gatilho decidir.
- Alexa: `AdicionarCompraIntent` com slot `item` `AMAZON.SearchQuery` (samples: "adicionar {item}", "adicionar {item} na lista",
  "colocar {item} na lista", "pôr {item} na lista de compras", "anotar {item} na lista") e `ListaDeComprasIntent`
  ("o que tem na lista", "o que falta comprar", "minha lista de compras", "lista do mercado").
  Função pura `parseShoppingUtterance(text: string, listNames: string[]): { list: string | null; items: string[] }` —
  remove sufixos " na lista (de compras|do X|da X)?", " na X"/" no X" quando X é uma lista existente (sem acento);
  separa itens por ", " e " e ". `SkillDeps` ganha `addShopping(items: string[], list: string | null): Promise<{added: string[]; skipped: string[]; list: string}>`
  e `shoppingSummary(): Promise<{list: string; items: string[]}[]>`; respostas: "Anotei leite e pão na lista Mercado." /
  "Leite já estava na lista." / "Na lista Mercado: leite, pão e 3 outros." / "Sua lista está vazia.". `help` cita "adicionar leite".
- Verificar: `cd mcp && npm test && npm run typecheck` (ou o script equivalente do package.json); idem `bridge`.

### Task 4: Início, rotas e integração (Onda 2 — depois de 2 e 3)
**Files:** Modify `app/lib/features/today/today_screen.dart`, `dashboard_cards.dart`, `dashboard_data.dart`, `app/lib/app/router.dart`,
`providers.dart` (se preciso), `shell.dart` (destinos `/academia`, `/compras` ativam "Mais" no celular; barra lateral ganha Academia e Compras),
`more_screen.dart` (itens Academia `Icons.fitness_center` e Compras `Icons.shopping_cart_outlined` no topo), `app/lib/main.dart`
(overrides Supabase), `app/test/helpers.dart` (parâmetros `fitnessRepo`, `shoppingRepo` com Memory padrão); tests
`app/test/features/today_test.dart`, `dashboard_test.dart`, `dashboard_data_test.dart` (atualizar os que testavam cartões removidos).
- `dashboard_data.dart`: `class TodayPlan { List<CalendarEvent> events; List<TaskItem> tasks; int moreTasks; }` e
  `TodayPlan buildTodayPlan(DateTime now, Iterable<CalendarEvent> events, Map<String, EventTag> tags, Iterable<TaskItem> tasks)`
  com as regras do spec §3 (séries frequentes = mesmo `seriesId` com ≥ 5 ocorrências em `[início de hoje, +7 dias)` na lista recebida;
  ordem: dia inteiro, depois por início; tarefas por prazo, máx. 5).
- `ParaHojeCard` (key `today-card`; evento atual destacado com "agora", prova com selo "Prova", terminados esmaecidos; marcar tarefa
  como feita no próprio cartão; "+N tarefas" → `/tarefas`; vazio "Dia livre"). Remova da Início os cartões e o botão de Notícias
  citados no spec; apague código que ficar sem uso (o widget Android e outros podem usar funções de `dashboard_data.dart` — confira antes).
- Testes: `buildTodayPlan` (academia fora por título e etiqueta, secundária fora, série diária fora, aula semanal dentro, tarefas de amanhã fora,
  atrasada dentro, concluída fora); Início mostra Para hoje, Academia, Compras, sem Notícias; 360 dp e tela larga sem overflow;
  Mais → Academia/Compras abrem.
- No fim: `cd app && flutter analyze` limpo.
