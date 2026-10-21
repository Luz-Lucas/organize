# Salvamento local primeiro — Plano

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:test-driven-development. Cada agente faz só a sua Task, sem commit.
> **Spec (aprovado):** `docs/superpowers/specs/2026-10-21-salvamento-local-design.md` — leia antes.

## Global Constraints
- pt-BR; estilo dos arquivos vizinhos; nada de dado pessoal no repo (público). Sem nuvem/VM/release/commit.
- Flutter em `~/development/flutter/bin` (JAVA_HOME=$HOME/development/android-studio/jbr, ANDROID_HOME=$HOME/Android/Sdk). Pouca RAM:
  testes por arquivo `cd app && TZ=America/Sao_Paulo flutter test <arquivos> -j 2`; não rode `dart format` no projeto inteiro;
  build só quando a Task pedir, depois `pkill -f '[G]radleDaemon'`.
- Tabelas sincronizadas (todas com chave `id`, exceto `user_settings` com chave `user_id`): `spaces, notes, tasks, events, event_tags,
  workouts, workout_exercises, workout_sessions, set_logs, shopping_lists, shopping_items, user_settings, wake_plans, wake_overrides`.
  `shopping_frequent` é só leitura (recebida, nunca enviada).

## Review Focus
1. Escrita offline → fechar o app → abrir sem rede → a alteração está lá; com rede, chega à nuvem uma vez só.
2. Linha alterada localmente (pendente) não é sobrescrita por uma versão mais velha que chega do realtime/carga.
3. Recusa permanente do servidor (RLS/constraint) não trava a fila: sai da fila, a cópia local volta ao da nuvem, aviso único.
4. Ordem da fila respeitada (criar lista → criar item da lista; criar ficha → exercícios), inclusive filhas que dependem do pai.
5. Sair da conta apaga o banco local; entrar com outra conta não mostra dados da anterior.

---

### Task 1 — Banco: último ganha (Onda 1)
`supabase/migrations/20261101000000_client_updated_at.sql`: em cada tabela sincronizada, `client_updated_at timestamptz not null default now()`;
função + gatilho `before update`: se `new.client_updated_at` **não mudou** em relação ao `old` (escrita da ponte/MCP/SQL que não manda o campo)
→ `new.client_updated_at := now()`; se mudou e é **menor** que `old.client_updated_at` → `return old` (ignora a atualização inteira);
senão segue. Garantir que todas as tabelas sincronizadas estão na publicação `supabase_realtime` (sem duplicar). pgTAP
`supabase/tests/database/client_updated_at_test.sql`: atualização mais nova vence, mais velha é ignorada (upsert com conflito também),
sem o campo vira now(), insert normal. Verificar `npx supabase migration up --local` e `npx supabase test db`; MCP (`cd mcp && npm test`)
e ponte (`cd bridge && npm test`) continuam verdes com as vars de `npx supabase status -o env`.

### Task 2 — Núcleo local + sincronizador (Onda 1)
Pasta nova `app/lib/sync/` (Dart puro + `sqlite3`/`sqlite3_flutter_libs` no pubspec — versões compatíveis com Flutter 3.47, Android, Linux e
Windows; nos testes do host use a lib do sistema ou um banco em memória). API fixa (as Tasks 3–5 usam):
- `class LocalStore` — `static Future<LocalStore> open(String path)`, `factory LocalStore.inMemory()`;
  `Stream<List<Map<String, dynamic>>> watch(String tbl)` (emite já o estado atual e a cada mudança da tabela);
  `Future<List<Map<String, dynamic>>> all(String tbl)`; `Future<Map<String, dynamic>?> get(String tbl, String id)`;
  `Future<void> put(String tbl, Map<String, dynamic> row)` e `putMany` (grava local + fila `upsert`, carimba `client_updated_at` = relógio
  injetável, em UTC ISO); `Future<void> remove(String tbl, String id)` e `removeMany` (apaga local + fila `delete`);
  `Future<void> wipe()`; `Stream<int> watchPending()`; métodos internos para o sincronizador aplicar dados remotos sem gerar fila.
  Chave da linha: `id`, exceto `user_settings` (`user_id`) — tabela de chaves configurável.
- `abstract interface class RemoteSource` — `Future<List<Map<String, dynamic>>> fetchAll(String tbl)`;
  `Future<void> upsert(String tbl, List<Map<String, dynamic>> rows)`; `Future<void> delete(String tbl, List<String> ids)`;
  `Stream<RemoteChange> changes(String tbl)` (`RemoteChange{type: upsert|delete, row}`); `SupabaseRemoteSource(SupabaseClient)`;
  `FakeRemoteSource` para testes (com falha de rede e recusa permanente simuláveis). Erros: `TransientSyncError` (rede, timeout, 5xx,
  429) e `PermanentSyncError(message)` (Postgrest 4xx/códigos 23xxx/42501…).
- `class SyncEngine` — `SyncEngine(LocalStore, RemoteSource, {required List<String> tables, List<String> readOnly = const [],
  DateTime Function()? now})`; `Future<void> start()` (carga inicial de todas + assina mudanças + envia fila), `Future<void> flush()`
  (envia a fila em ordem, agrupando upserts consecutivos da mesma tabela; transitório = para e tenta de novo com espera 1 s, 2 s, 4 s…
  até 60 s; permanente = tira da fila, rebusca a linha da nuvem para corrigir a cópia local e emite em `rejections`),
  `Future<void> refresh()` (recarrega tudo — usado ao reconectar/voltar ao app), `Stream<SyncRejection> rejections`
  (`tbl, id, message`), `Stream<SyncState> state` (`pending`, `online`, `lastError`), `Future<void> dispose()`.
  Regra de recebimento: linha remota só substitui a local se não houver item pendente dessa linha na fila **ou** se o
  `client_updated_at` remoto for mais novo que o pendente; `delete` remoto apaga mesmo assim e descarta upserts pendentes dessa linha
  (apagar ganha). Carga completa remove localmente o que sumiu da nuvem (sem pendência).
- Testes extensos com `LocalStore.inMemory()` + `FakeRemoteSource` cobrindo o Review Focus 1–4 e persistência (abrir o arquivo de novo
  mantém linhas e fila).

### Task 3 — Repositório principal local-primeiro (Onda 2, depois de 1 e 2)
`app/lib/data/local_repository.dart`: `LocalFirstRepository implements Repository` sobre `LocalStore` (espaços, notas, tarefas, eventos,
séries, etiquetas). Mesma ordem/filtros que `SupabaseRepository` (ordenação em Dart); `seedEventTags` continua chamando a RPC do servidor
quando online (ou fica para o próximo envio). Testes: o mesmo contrato dos testes atuais do `MemoryRepository`/`SupabaseRepository`.
Não mexa em `main.dart` (Task 5 liga tudo).

### Task 4 — Academia e Compras local-primeiro (Onda 2)
`LocalFirstFitnessRepository`, `LocalFirstShoppingRepository` (mesmos contratos). Compras: item novo sem seção grava `section: null`
localmente e o app mostra como "Outros" até a nuvem devolver; `finishShopping` = `removeMany` dos marcados; frequentes vêm da tabela
somente leitura. Academia: marcar série reaproveita o `id` se já houver registro daquela série (idempotente) e o envio de `set_logs`
usa `onConflict: 'session_id,exercise_id,set_index'`. Testes de contrato. Não mexa em `main.dart`.

### Task 5 — Ajustes, despertares, ligação e telas (Onda 3, depois de 3 e 4)
`LocalFirstSettingsRepository`; wake plans/overrides do `AlexaRepository` em local-primeiro (comandos, dispositivos, rotinas e status
continuam online). `main.dart`: abre o `LocalStore` por usuário (arquivo em `getApplicationSupportDirectory()/sync/<userId>.db`),
cria o `SyncEngine`, dá `start()` no login, `refresh()` ao voltar ao app e ao reconectar, `wipe()` + fecha ao sair da conta; troca os
overrides dos repositórios pelos local-primeiro (os de Supabase continuam existindo para o segundo plano se preciso). Indicador: a faixa
global (`lib/app/connection_banner.dart`) passa a "N alterações aguardando envio" quando há fila parada há > 4 s, e rejeições viram aviso
único (SnackBar) "Não foi possível salvar … (motivo)". Remover/ajustar mensagens "Não foi possível …" que só existiam por queda de
conexão nas telas (as escritas locais não falham por rede). Segundo plano (`widget_background.dart`, `reminder_background.dart`):
enviar a fila e ler do banco local quando existir. Testes: fluxo completo com `FakeRemoteSource` via `pumpApp` (offline → escreve →
volta → envia). No fim: suíte inteira UMA vez, `flutter analyze`, `flutter build apk --debug` e `flutter build linux --debug` UMA vez cada.
