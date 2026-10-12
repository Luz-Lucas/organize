# Séries na agenda, Despertares na Início, GitHub, Google Drive (Documentos) e importação de notas — Design e Plano

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development ou executing-plans. TDD (superpowers:test-driven-development) em todo código novo.

**Aprovado no chat (2026-10-12):** "pode fazer as novas implementações, faça tudo". Já entregue antes deste plano: correção do widget Agenda e Tarefas (`<View>` → `<FrameLayout>`, commit 5d3a2e2).

## Regras comuns (todas as tasks)

- pt-BR em toda a UI e mensagens. Cores só de tokens/tema (`context.org`, `Theme.of(context).colorScheme.error` para erro).
- `export PATH="$HOME/development/flutter/bin:$PATH"`. App: `cd app && flutter analyze` limpo e `TZ=America/Sao_Paulo flutter test --exclude-tags integration` verde **ao final** (a suíte é compartilhada: rode a sua parte durante o trabalho e a suíte inteira no fim; falha de outro agente → relate, não conserte o arquivo dele).
- Bridge: `cd bridge && npx vitest run` + `npx tsc -p tsconfig.typecheck.json`. MCP: `cd mcp && npx vitest run` + typecheck equivalente. Edge Functions: testes Deno no padrão de `supabase/functions/_shared/*_test.ts`/`gmail-*/handler_test.ts` (`deno test` como os existentes).
- Banco **só local**: `npx supabase migration up --local`, `npx supabase test db` (pgTAP em `supabase/tests/database/`). Nunca `db reset`, nunca `--linked`, nunca a nuvem, nunca a VM. Ninguém faz `git commit`/`stash`. Só a Task D roda Gradle/`flutter build`.
- **Arquivos compartilhados** (`app/lib/app/router.dart`, `app/lib/features/more/more_screen.dart`, `app/lib/main.dart`, `app/test/helpers.dart`, `app/lib/features/settings/settings_screen.dart`, `supabase/config.toml`, `mcp/src/tools/index.ts`, `app/android/app/src/main/AndroidManifest.xml`): edições pequenas com Edit, ancoradas, relendo o arquivo imediatamente antes; nunca reescrever o arquivo inteiro.
- Migrações com timestamps reservados: A `20261017000000_event_series.sql`, B `20261018000000_wake_overrides.sql`, D `20261019000000_google_drive.sql`.
- Segredos/tokens nunca em logs, nunca no app. Toda consulta filtra por `user_id`.

---

## Task A — Repetição de eventos e edição/exclusão em série

**Design.** Ocorrências continuam materializadas em `events` (a ponte, os widgets, o MCP e o painel leem linhas prontas). Coluna nova `series_id uuid null` (índice `(user_id, series_id, starts_at)`), mais `recurrence jsonb null` só informativa (a regra usada para gerar: `{"freq":"daily|weekdays|weekly|biweekly|monthly","days":[1..7],"until":"YYYY-MM-DD"|null,"count":int|null}`, dias ISO 1=seg..7=dom).

**Migração `20261017000000_event_series.sql`:** `alter table events add column series_id uuid, add column recurrence jsonb check (recurrence is null or jsonb_typeof(recurrence)='object')`; índice; **backfill** determinístico: para `source='google'` e `external_id like '%\_%'`, `series_id = uuid gerado por base` (`split_part(external_id,'_',1)`); para `source='plano'` e `external_id like '%:%'`, base = `split_part(external_id,':',1)`; só agrupar bases com **≥ 2** linhas do mesmo `user_id` (use `md5(user_id || source || base)::uuid` para ser determinístico). pgTAP: backfill agrupa corretamente, base com 1 linha fica `null`, check do jsonb.

**Domínio (`app/lib/domain/calendar_event.dart` + novo `app/lib/domain/recurrence.dart`):**
- `CalendarEvent` += `seriesId`, `recurrence` (`Recurrence?`) com `fromMap/toMap/copyWith` (mantenha `withoutSpace` preservando os campos novos).
- `enum RepeatFreq { none, daily, weekdays, weekly, biweekly, monthly }` com `label` pt-BR ("Não repete", "Todo dia", "Dias úteis (seg–sex)", "Toda semana", "A cada 2 semanas", "Todo mês").
- `Recurrence { freq, days (Set<int>), until (DateTime?), count (int?) }` + `List<DateTime> expandStarts(DateTime firstStart)`: gera inícios na hora local do primeiro; `until` inclusivo; `count` ≥1; limite duro **366 ocorrências e 1 ano** a partir do primeiro; `weekly/biweekly` com `days` vazio = dia da semana do primeiro; `monthly` no mesmo dia do mês (meses sem esse dia são pulados: 31 → só meses com 31); horário de verão não existe em America/Sao_Paulo, mas use `DateTime(y,m,d,h,min)` local (não somar Duration). Duração de cada ocorrência = a do primeiro (eventos que viram o dia continuam funcionando).
- `enum SeriesScope { one, following, all }`.
- `SeriesOps` (funções puras sobre listas): `buildSeries(CalendarEvent template, Recurrence r, String Function() newId)` → ocorrências com mesmo `seriesId`; `applyEdit(series, target, edited, scope)` → lista de upserts (para `following`: as ocorrências ≥ target recebem **novo** `seriesId`, aplicam título/local/espaço/dia-inteiro e o **deslocamento** de horário de início e a nova duração; `all`: todas recebem o mesmo deslocamento/duração e campos; `one`: só o alvo, e ele **sai** da série — `seriesId=null`); `deleteIds(series, target, scope)`.

**Repositório:** `Repository` += `Future<void> upsertEvents(List<CalendarEvent>)` e `Future<void> deleteEvents(List<String> ids)` (Memory e Supabase; Supabase em lote: `upsert(list)` e `delete().inFilter('id', ids)`; mapeie erros em `RepositoryException`). Não remova `upsertEvent/deleteEvent`.

**UI (`app/lib/features/agenda/event_dialog.dart`, `agenda_screen.dart`, `mobile_calendar.dart`):**
- No editor de **evento novo**: seletor "Repetir" (`Key('event-repeat')`, opções `RepeatFreq`); para `weekly/biweekly` chips dos dias (`Key('event-repeat-day-<1..7>')`, pré-selecionado o dia do início); fim: "Até" (data, padrão início + 3 meses, `Key('event-repeat-until')`) ou "Vezes" (`Key('event-repeat-count')`, 1–366). Resumo em texto ("Toda semana às ter e qui, até 15 dez · 18 ocorrências", `Key('event-repeat-summary')`). Ao salvar: `upsertEvents(buildSeries(...))`.
- Editar/excluir um evento com `seriesId` ≠ null: diálogo "Este evento se repete" com três opções (`Key('series-scope-one'|'series-scope-following'|'series-scope-all')`: "Só este evento", "Este e os seguintes", "Todos os eventos da série") e Cancelar. Exclusão mantém a confirmação/desfazer atual (`showUndo` em `lib/ui/common.dart`): o desfazer restaura todos os eventos apagados (`upsertEvents`).
- Em eventos de série mostrar um ícone de repetição (Icons.repeat, 14 dp) na lista/agenda.
- Editar a regra de repetição de uma série existente: **fora do escopo** (o usuário apaga "este e os seguintes" e cria de novo); o seletor "Repetir" só aparece para evento novo.

**MCP (`mcp/src/tools/agenda.ts`):** `create_event` aceita opcional `repeat: { freq, days?, until?, count? }` (mesmas regras/limites; implemente a expansão em TS espelhando o Dart, com testes); `delete_event` aceita `scope?: 'one'|'following'|'all'` (padrão `one`). Anote no description em pt-BR.

**Testes:** `test/domain/recurrence_test.dart` (cada freq, until vs count, limites 366/1 ano, mensal dia 31, evento que vira o dia, weekly sem dias), `SeriesOps` (one/following/all para editar e excluir), telas (`test/features/agenda_series_test.dart`: criar semanal ter+qui cria N eventos com o mesmo seriesId; excluir "este e os seguintes" remove só os ≥; desfazer restaura; editar "todos" desloca horário; evento sem série não mostra o diálogo de escopo), MCP (vitest), pgTAP.

**Arquivos:** só os acima + testes. Não toque em `today/`, `home/`, `alexa`, `widgets/`.

---

## Task B — Despertares na Início + "só amanhã" (override por data)

**Banco `20261018000000_wake_overrides.sql`:** `wake_overrides(user_id uuid not null default auth.uid() references auth.users on delete cascade, plan_id uuid not null references wake_plans(id) on delete cascade, run_date date not null, skip boolean not null default false, time time null, created_at timestamptz not null default now(), primary key (plan_id, run_date), check (skip or time is not null))` + RLS do dono (select/insert/update/delete com `user_id = auth.uid()`) + **o plan_id precisa ser do mesmo usuário** (policy `with check (exists (select 1 from wake_plans p where p.id = plan_id and p.user_id = auth.uid()))`) + realtime. pgTAP: RLS (outro usuário não lê/escreve, não consegue apontar plano alheio), check skip/time.

**Ponte (`bridge/src/scheduler.ts`, `supabase-store.ts`, `main.ts`):** `WakeOverride { planId, runDate, skip, time: string|null }`. `occurrence(plan, runDate, tz, overrides?)`: se houver override para `(plan.id, runDate)` → `skip` ⇒ `null`; senão usa `override.time` (**mesmo que o dia da semana não esteja em `plan.days`**); sem override → regra atual. `planWakeActions(plans, runs, now, tz, opts, overrides = [])` repassa (o re-armar/cancelar do alarme reserva já segue sozinho). Store: `loadOverrides(userId, fromDate, toDate)` (ontem..amanhã+1), filtrando por `user_id`. Overrides antigos (run_date < hoje − 7) são apagados pela ponte (best effort, uma vez por hora). Testes vitest: skip cancela o reserva armado; mudar horário re-arma; override em dia fora de `days` dispara; sem override nada muda.

**MCP (`mcp/src/tools/wake.ts`):** `set_wake_override { plan_id, date (YYYY-MM-DD), skip?: boolean, time?: "HH:MM" }` e `clear_wake_override { plan_id, date }`; `list_wake_plans` inclui overrides futuros. Testes.

**App:**
- Domínio `WakeOverride` (`lib/domain/alexa.dart` ou arquivo novo `lib/domain/wake_override.dart`), `AlexaRepository` += `watchOverrides()`, `setOverride(...)`, `clearOverride(planId, date)` (Memory + Supabase), provider `wakeOverridesProvider`.
- Função pura `nextWake(plan, overrides, now)` → `DateTime?` (reaproveite/estenda `lib/features/home/wake_next.dart`; ela já existe para "Toca em …"; passe a considerar overrides, inclusive dia extra e pulo) e o editor do despertar passa a usar a versão com overrides.
- **Cartão "Despertares"** (`lib/features/today/wake_card.dart`, `Key('wake-card')`) no painel da Início, logo depois de "Agora e a seguir" (edite `today_screen.dart`/`dashboard_cards.dart` só o necessário; no desktop vai para a coluna esquerda). Conteúdo: até 4 despertares (ativos primeiro, ordenados pelo próximo toque); cada linha: nome, hora (com o horário de amanhã se houver override), dias resumidos, `Switch` liga/desliga (`Key('wake-toggle-<id>')`, grava `enabled` via `upsertWakePlan`), texto "Toca amanhã às 06:30 · em 7 h 20 min" / "Desligado" / "Amanhã: pulado"; toque na linha → `context.push('/casa/despertar/<id>')`; botão "Só amanhã" (`Key('wake-tomorrow-<id>')`) abre folha: "Mudar horário só amanhã" (time picker) / "Não tocar amanhã" / "Voltar ao normal" (se já houver override) → grava/limpa o override de **amanhã** (data local). "+ Novo despertar" (`Key('wake-new')`) → editor de despertar novo (mesma rota usada em `/casa`). Sem despertares: texto "Nenhum despertar" + botão. Sem ponte configurada continua mostrando (os dados são do banco).
- Testes de widget (painel a 360 dp sem overflow com 1.3x; toggle grava; só amanhã muda horário/pula/volta; tocar abre editor; ordenação), domínio (`nextWake` com overrides), repositório memória.

**Arquivos:** os acima; `today_screen.dart` e `dashboard_cards.dart` com edições pequenas. Não toque em `agenda/`, `notes/`, `settings/`, `email/`.

---

## Task C — GitHub: issues pelo app

**Edge Function `supabase/functions/github/`** (`index.ts` + `handler.ts` + `handler_test.ts`, JWT do usuário verificado como `gmail-connect`; `verify_jwt=true` no `config.toml`). Segredos: `GITHUB_TOKEN` (fine-grained, Issues read/write + Metadata read) e opcional `GITHUB_REPOS` (lista `owner/repo` separada por vírgula; se ausente, usa os repositórios que o token enxerga via `GET /user/repos?per_page=100&sort=pushed`). Também restrito ao dono: `GITHUB_ALLOWED_USER_ID` (uuid do usuário do Supabase; outro usuário → 403). POST `{action, ...}`:
- `repos` → `[{fullName, private}]`
- `list` `{repo, state:'open'|'closed'|'all'}` → `[{number,title,state,labels:[name],createdAt,url,comments}]` (só issues, filtra `pull_request`), 30 mais recentes.
- `create` `{repo, title (1..256), body? (≤ 65536), labels?: string[]}` → `{number,url}`
- `set_state` `{repo, number, state:'open'|'closed'}` → `{ok:true}`
- `comment` `{repo, number, body}` → `{ok:true}`
- `labels` `{repo}` → `[name]`
Repo sempre validado contra a lista permitida; erros do GitHub → `{error}` em pt-BR com status 502/4xx; `GITHUB_TOKEN` ausente → 500 "GitHub não configurado". Headers `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28`, `User-Agent: organizacional`. Testes com `fetch` falso.

**App:** `lib/data/github_repository.dart` (interface + `MemoryGithubRepository` + `SupabaseGithubRepository` via `functions.invoke('github')`), domínio `lib/domain/github.dart`. Tela `lib/features/github/github_screen.dart` em rota `/github` (`context.push` a partir de **Mais**, item "GitHub" com ícone `Icons.code`): seletor de repositório (lembra o último em `SharedPreferences` **se** o projeto já usa; senão memória), abas Abertas/Fechadas, lista (número, título, rótulos, "há 2 d", comentários), puxar para atualizar, tocar abre detalhes em folha com "Abrir no GitHub" (`linkOpenerProvider`), "Fechar/Reabrir", "Comentar". FAB "Nova issue" (`Key('github-new')`) → formulário (título obrigatório, descrição, rótulos existentes como chips). Estado "GitHub não configurado" explica o passo do token. **Atalho na tarefa:** no editor de tarefa (`task_dialog.dart`) ação "Criar issue no GitHub" (`Key('task-to-issue')`) que abre o formulário preenchido com título/descrição da tarefa e, ao criar, anexa o link da issue ao fim da descrição da tarefa. Testes de widget e repositório.

**MCP:** `create_github_issue {repo, title, body?, labels?}` e `list_github_issues {repo, state?}` chamando a Edge Function **não** (o MCP roda na VM sem JWT de usuário): **fora do escopo**; não implemente no MCP.

**Docs:** `supabase/functions/GITHUB_SETUP.md` (criar o token fine-grained: Repository access = os repositórios desejados; Permissions: Issues RW, Metadata R; expiração 1 ano; `npx supabase secrets set GITHUB_TOKEN=... GITHUB_ALLOWED_USER_ID=...`).

**Arquivos:** os acima + `router.dart`, `more_screen.dart`, `main.dart`, `helpers.dart`, `task_dialog.dart` (pequeno), `config.toml` (bloco da função). Não toque em `agenda/`, `today/`, `notes/`, `documents/`.

---

## Task D — Google Drive (Documentos) + importar/compartilhar para notas (Samsung Notes e qualquer app)

**Conta e escopo.** Conta Google `sua-conta@exemplo.com` (a do login do Supabase), escopo `https://www.googleapis.com/auth/drive` (gerenciar o Drive inteiro: pastas existentes, mover, compartilhar). Mesmo cliente OAuth do Gmail (um projeto no Google Cloud; o usuário só adiciona a Drive API e o escopo). Mesmo padrão de segurança do Gmail: refresh token cifrado (AES-256-GCM, `GMAIL_TOKEN_KEY`) em `google_accounts` (provider `drive`), nunca vai ao app.

**Banco `20261019000000_google_drive.sql`:** `google_accounts.provider` check passa a aceitar `('gmail','drive')`; tabela `drive_state(user_id pk, account_email, status text check in ('not_connected','ok','auth_required','error'), root_folder_id text, message text, connected_at timestamptz)` com RLS só-leitura do dono (como `email_state`). pgTAP.

**Edge Functions (reaproveitar `_shared/gmail.ts`):** generalize sem quebrar o Gmail (os testes existentes do Gmail continuam verdes):
- `gmail-connect` aceita `{provider?: 'gmail'|'drive', email?}` (padrão `gmail`); o `state` assinado carrega o provider; `buildConsentUrl` escolhe o escopo pelo provider. `gmail-callback` grava `google_accounts` com o provider do state e, para `drive`, cria/acha a pasta raiz **"Organizacional"** no Meu Drive e grava `drive_state(status='ok', root_folder_id, account_email)`. (Mantenha os nomes das funções `gmail-connect`/`gmail-callback`: o redirect URI já cadastrado não muda.)
- Nova função **`drive`** (JWT do usuário; `verify_jwt=true`): obtém access token do refresh (cache em memória por usuário até expirar) e responde POST `{action, ...}`:
  - `list {folderId?}` (padrão raiz "Organizacional"; `'root'` = Meu Drive) → `{folder:{id,name,parents}, items:[{id,name,mimeType,isFolder,size,modifiedTime,webViewLink,iconLink,shared}]}` (sem lixeira, pastas primeiro, nome asc, até 200)
  - `search {q}` → itens (nome contém, escapando aspas)
  - `create_folder {parentId, name}`; `rename {id, name}`; `move {id, toFolderId}` (troca parents); `trash {id}`; `restore {id}`
  - `share {id, email, role:'reader'|'writer'|'commenter', notify?:bool}`; `share_link {id, enabled:bool}` (cria/remove permissão `anyone` reader) → `{webViewLink}`; `permissions {id}` → `[{id,email,role,type}]`; `unshare {id, permissionId}`
  - `upload_session {parentId, name, mimeType, size}` → `{uploadUrl}` (sessão **resumable** do Drive criada no servidor; o app faz `PUT` do arquivo direto nessa URL, sem token)
  - `disconnect` (revoga, apaga `google_accounts`/`drive_state` do usuário)
  Erros do Google → `{error}` pt-BR; 401/invalid_grant → marca `auth_required`. Testes com `fetch` falso.

**App — Documentos:** `lib/domain/drive.dart`, `lib/data/drive_repository.dart` (interface, Memory, Supabase), tela **`/documentos`** (`lib/features/documents/documents_screen.dart`): navegação por pastas com trilha (breadcrumb) e voltar para a pasta anterior (integra com o `BackHandler`/`popOrGo` de `lib/app/back_navigation.dart`), alternar "Organizacional"/"Meu Drive", busca, lista com ícone por tipo, tamanho, data; ações por item (menu e long-press): Abrir (webViewLink no app/navegador via `linkOpenerProvider`), Renomear, Mover para… (seletor de pasta), Compartilhar (folha: link público liga/desliga + copiar; convidar por e-mail com papel; lista de quem tem acesso com remover), Mover para a lixeira (com desfazer → `restore`); FAB: "Nova pasta" e "Enviar arquivo" (`file_picker`, já existe? se não, adicionar; upload via `upload_session` + `http` PUT com progresso; limite 100 MB, aviso acima). Estados: não conectado → botão para Ajustes; `auth_required` → reconectar. Entrada em **Mais** ("Documentos", `Icons.folder_outlined`) e cartão em **Ajustes** "Google Drive" (conectar/desconectar, mesmo padrão do `GmailCard`; reaproveite estilo). Rota com `context.push`.

**App — Importar/compartilhar para o Organizacional (Samsung Notes e qualquer app):**
- **Android share target:** `MainActivity` recebe `ACTION_SEND`/`ACTION_SEND_MULTIPLE` com `text/plain`, `text/*`, `application/pdf`, `image/*`, `application/vnd.openxmlformats-officedocument.wordprocessingml.document`, `application/msword` (intent-filters no manifesto; use o pacote `receive_sharing_intent` **ou** um MethodChannel/EventChannel próprio em Kotlin — escolha o que funcionar com o embedding atual e `launchMode`; app aberto e app fechado). Ao receber: abre a folha "Salvar no Organizacional" (`Key('share-sheet')`) com o que chegou e destino: **texto** → nova nota (título = primeira linha até 80 caracteres, corpo = resto; espaço escolhido, padrão "Importadas" criado se não existir); **arquivos** → enviados ao Drive na pasta "Organizacional/Importados" (criada se faltar) **e** uma nota com o nome do arquivo e o link (`webViewLink`) para abrir em qualquer dispositivo; sem Drive conectado → explica e oferece só a nota de texto (para texto) ou abrir Ajustes.
- **Importação em lote** (Notas → menu "Importar arquivos", `Key('notes-import')`, também no Linux): `file_picker` múltiplo; `.txt`/`.md` viram notas (conteúdo convertido para o formato atual do editor — leia como `note_screen.dart`/`notes` guardam o corpo e use o conversor de markdown que o projeto já tem, se houver; senão parágrafos simples); `.pdf/.docx/imagens` vão ao Drive + nota com link. Resumo final "12 notas criadas, 3 arquivos enviados".
- Samsung Notes: no texto de ajuda (folha e Ajustes → Drive) explique "No Samsung Notes: abra a nota → Compartilhar → Organizacional (texto) ou Salvar como PDF e compartilhar". Não há API do Samsung Notes: **não** tente ler os arquivos `.sdocx`.

**Docs:** renomeie/estenda `supabase/functions/GMAIL_SETUP.md` → `GOOGLE_SETUP.md` (manter um `GMAIL_SETUP.md` curto apontando para o novo) com a Drive API e o escopo `drive` no mesmo projeto e cliente.

**Testes:** Edge Functions (deno), pgTAP, repositório memória, telas (navegar pastas, voltar, criar pasta, renomear, mover, lixeira+desfazer, compartilhar link e e-mail, upload com repo falso, estados não conectado/expirado), folha de compartilhamento (texto → nota; arquivo → Drive + nota; sem Drive), importação em lote com `FilePicker` falso (injete via provider). **Build:** `flutter build apk --debug --dart-define-from-file=env.json` verde + conferir no manifesto mesclado os intent-filters de SEND.

**Arquivos:** os acima + `router.dart`, `more_screen.dart`, `main.dart`, `helpers.dart`, `settings_screen.dart`, `notes_screen.dart` (só o menu Importar), `AndroidManifest.xml`, `MainActivity.kt`, `pubspec.yaml` (dependências novas), `config.toml`. Não toque em `agenda/`, `today/`, `tasks/`, `github/`.

---

## Task E (coordenador)

Integrar, suíte completa (app, bridge, mcp, deno, pgTAP), revisão independente, commit/push, aplicar migrações na nuvem (A → B → D), publicar funções (`github`, `drive`, `gmail-connect`, `gmail-callback`), ponte+MCP na VM (docker save/load), APK + Linux, guiar o usuário: Google Cloud (Drive API + escopos, cliente OAuth → `GOOGLE_CLIENT_ID/SECRET`) e token do GitHub.
