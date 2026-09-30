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

## Nuvem (Supabase)
Para publicar o schema num projeto Supabase de verdade (não o local do Docker):
```bash
npx supabase login
npx supabase link --project-ref <ref-do-projeto>
npx supabase db push
```
Depois, crie o usuário pelo Dashboard (Authentication → Add user) — o app não
tem tela de cadastro.

**Importante:** logo após publicar, desabilite o cadastro público em
Authentication → Sign In / Providers → "Allow new users to sign up". O
`enable_signup = true` em `supabase/config.toml` vale só para o ambiente local
(Docker) e não deve ser levado para a nuvem com `supabase config push` — nesse
projeto o cadastro é sempre feito manualmente pelo Dashboard.

## Testes de integração (Supabase local)
```bash
eval "$(npx supabase status -o env)"
cd app && SUPABASE_URL="$API_URL" SUPABASE_ANON_KEY="$ANON_KEY" flutter test --tags integration
```

## Notícias
- Coleta: Edge Function `news-fetch` (a cada 20 min via `pg_cron`); testes com `deno test supabase/functions/news-fetch/`.
- Verificar o catálogo de feeds: `deno run --allow-net supabase/functions/news-fetch/check_feeds.ts`.
- Local: `npx supabase functions serve news-fetch --env-file supabase/functions/.env` (`CRON_SECRET` nesse arquivo).
- Filtro (interesses/bloqueios): função SQL `news_feed`. É a mesma regra usada pelo app, pela Alexa e pelo Claude.
- Limitação conhecida (SSRF): o endpoint `validate` busca qualquer URL http/https em nome de um usuário logado. Aceito por ser uso pessoal; não exponha o projeto a usuários não confiáveis (mantenha o cadastro público desligado).

### Publicar na nuvem
```bash
cd /home/only/organizacional
SEGREDO=$(openssl rand -hex 24)
npx supabase db push
npx supabase functions deploy news-fetch
npx supabase secrets set CRON_SECRET="$SEGREDO"
echo "$SEGREDO"   # use no SQL abaixo
```
No **SQL Editor** do painel do Supabase (troque `<ref>` e `<segredo>`), crie os segredos do Vault usados pelo job `news-fetch` do `pg_cron`:
```sql
select vault.create_secret('https://<ref>.supabase.co/functions/v1/news-fetch', 'news_fetch_url');
select vault.create_secret('<segredo>', 'cron_secret');
```

### Verificar a coleta agendada
Ligue algumas fontes no app (build de produção), espere até 20 minutos e rode no SQL Editor:
```sql
select status, return_message, start_time from cron.job_run_details order by start_time desc limit 3;
select count(*), max(fetched_at) from news_items;
select status_code, content from net._http_response order by created desc limit 3;
```
Esperado: `succeeded`; `count` > 0; resposta HTTP 200 com `"failures":[]` (ou só as fontes que caíram naquele momento).

### Teste manual
Contra o Supabase local: `npx supabase functions serve news-fetch --env-file supabase/functions/.env` (terminal separado) e `cd app && flutter run -d linux --dart-define-from-file=env.json`.
1. Em Notícias, toque em ⚙ e ligue "G1 / Principais".
2. Volte e toque em ↻: as manchetes aparecem.
3. Coloque um interesse que esteja em alguma manchete e salve: ela sobe com ★.
4. Adicione `https://g1.globo.com` como feed próprio: deve aparecer o erro (não é um feed RSS) e a fonte não é salva.

## Builds
```bash
cd app
flutter build linux --release --dart-define-from-file=env.json
flutter build apk --release --dart-define-from-file=env.json
```

## Próximas fases
Veja `docs/superpowers/specs/2026-09-28-organizacional-design.md`: Claude via MCP, Google Agenda, GitHub, anexos (YouTube/PDF/docx).
