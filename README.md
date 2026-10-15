# Organizacional

Agenda, tarefas, matérias, trabalhos e hobbies num só lugar. Flutter (Linux/Windows/Android) + Supabase.

## Estrutura
Guia completo (arquitetura, como acrescentar/tirar funcionalidades, rodar sem servidor): [`docs/GUIA-DO-DESENVOLVEDOR.md`](docs/GUIA-DO-DESENVOLVEDOR.md).

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
- Limitação conhecida (SSRF): o endpoint `validate` busca qualquer URL http/https em nome de um usuário logado, e a coleta agendada busca todo feed próprio cadastrado (um usuário logado também pode gravar `feed_url` direto pela API, sem passar por `validate`). Aceito por ser uso pessoal; não exponha o projeto a usuários não confiáveis (mantenha o cadastro público desligado).

### Publicar na nuvem
```bash
# na raiz do repositório
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

## Alexa (ponte na VPS)

Código em `bridge/`. Testes: `cd bridge && npx vitest run` (integração com `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` do Supabase local).

> **Status:** a ponte está no ar na VPS (Echos, rotinas e dispositivos sincronizados) e o MCP também. Os passos abaixo ficam como guia de reinstalação. Ainda falta conferir o passo 5 (skill no console da Alexa) e o teste manual da Fase 3 (despertar tocando sozinho no horário).

### 1. Publicar a migration na nuvem (na sua máquina)
```bash
npx supabase db push
```
Aplica a migration da Alexa (tabelas `alexa_*`, `wake_plans`, `wake_runs`, RPC `claim_wake_run`).

### 2. Preparar a VPS (Ubuntu, usuário com sudo)
```bash
sudo apt-get update && sudo apt-get install -y docker.io docker-compose-v2 git ufw
sudo usermod -aG docker "$USER" && newgrp docker
sudo ufw allow OpenSSH && sudo ufw allow 80 && sudo ufw allow 443 && sudo ufw --force enable
git clone <seu-repositório> organizacional && cd organizacional/bridge
cp .env.example .env && nano .env
```
Preencha o `.env` (fica só na VPS, nunca vai para o git):
- `DOMAIN`: crie um subdomínio grátis em https://www.duckdns.org apontando para o IP da VPS.
- `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY`: Supabase, Project Settings → API.
- `ORGANIZACIONAL_USER_ID`: Authentication → Users, o UUID do seu usuário.
- `ALEXA_ALLOWED_USER_ID`: deixe vazio por enquanto (passo 5).
- Os demais (`TZ_NAME`, `ALEXA_COOKIE_FILE`, `AMAZON_PAGE`, `ALEXA_SERVICE_HOST`, `PORT`, `LOGIN_PROXY_PORT`) já vêm com valores certos para o Brasil.

### 3. Login da Alexa
Na VPS:
```bash
docker compose build
docker compose run --rm -p 127.0.0.1:3001:3001 bridge node dist/scripts/login.js
```
No seu PC: `ssh -L 3001:127.0.0.1:3001 <usuario>@<vps>` e abra http://localhost:3001. Entre na conta Amazon (com 2FA, se tiver). Esperado: a VPS imprime `Login salvo em /data/alexa-cookie.json` e o comando termina. Contas brasileiras fazem login por `amazon.com` + `pitangui.amazon.com` (padrão do `.env.example`); com `amazon.com.br` o login devolveu "Houve um problema". Se a Amazon pedir troca de senha durante o login, conclua por essa mesma página.

Teste de fumaça:
```bash
docker compose run --rm bridge node dist/scripts/smoke.js --speak <SERIAL_DO_ECHO> Teste da ponte
```
Esperado: lista Echos (`id` = serial), dispositivos e rotinas, e o Echo fala "Teste da ponte".
- Se `Dispositivos` vier vazio mas você tem lâmpadas na Alexa, salve a resposta crua de `getSmarthomeEntities` como `bridge/test/fixtures/entities.json`, adicione um caso em `mappers.test.ts` e ajuste `mapSmartEntities` até passar.
- **Verificar:** o `alexa-remote2` fixa o locale `de-DE` em `playMusicProvider`. Confirme no smoke test/despertar de teste que a busca do Spotify em pt-BR toca a música certa; se não tocar, investigue esse locale.

### 4. Subir o serviço
```bash
docker compose up -d --build && sleep 20 && curl -s https://$DOMAIN/health && docker compose logs --tail=20 bridge
```
Esperado: `{"ok":true}`; logs com `ouvindo na porta 8080` e `sincronizado: N Echos, ...`. No SQL Editor do Supabase, `select state, last_seen from alexa_bridge_status;` mostra `ok` com horário recente.

### 5. Criar a skill no console
Em https://developer.amazon.com/alexa/console/ask:
1. **Create Skill**: nome "Organizacional", idioma **Portuguese (BR)**, modelo **Custom**, hospedagem **Provision your own**, template **Start from scratch**.
2. **Interaction Model → JSON Editor**: cole `bridge/skill/interaction-model.pt-BR.json` → **Save** → **Build skill**.
3. **Endpoint**: HTTPS → `https://<DOMAIN>/alexa`, certificado **"My development endpoint has a certificate from a trusted certificate authority"** → **Save**.
4. **Test**: ative **Development** e digite "abrir organizacional".

Esperado: a skill responde "Skill ainda não configurada..." e `docker compose logs bridge | grep "skill chamada"` mostra `amzn1.ask.account...`. Copie esse valor para `ALEXA_ALLOWED_USER_ID` no `.env`, rode `docker compose up -d` e teste de novo: o resumo do dia é falado. No Echo: "Alexa, abre organizacional".

### Operação
- Subir/atualizar: `cd bridge && docker compose up -d --build`. Saúde: `https://$DOMAIN/health`.
- **Refazer o login da Alexa** (quando o app avisar):
  1. Na VPS: `docker compose run --rm -p 127.0.0.1:3001:3001 bridge node dist/scripts/login.js`
  2. No seu PC: `ssh -L 3001:127.0.0.1:3001 <usuario>@<vps>` e abra http://localhost:3001
  3. `docker compose restart bridge`
- Diagnóstico: `docker compose run --rm bridge node dist/scripts/smoke.js`.
- Despertares: se a ponte cair, o **alarme reserva** (criado até 24 h antes no próprio Echo) toca 10 min depois do horário.
- Skill: "Alexa, abre organizacional" / "Alexa, pergunte ao organizacional quais são as notícias".

### Teste manual da Fase 3 (com a ponte no ar)
Rode o app: `cd app && flutter run -d linux --dart-define-from-file=env.json`.
1. Casa → ⟳ (sincronizar): aparecem os Echos, as rotinas e os dispositivos; aparece "Feito.".
2. Toque em ▶ numa rotina: o Echo executa.
3. Crie um despertar para daqui a 5 minutos, com seu Echo e uma busca do Spotify; toque em **Testar agora**: toca a música e fala o resumo.
4. Espere o horário: o despertar toca sozinho. No SQL Editor, `select status, note from wake_runs order by created_at desc limit 1;` mostra `done`, e o alarme "(reserva)" some do app Alexa.
5. `docker compose stop bridge` na VPS; em até 3 minutos, Hoje mostra o aviso (se houver despertar ativo). Rode `docker compose start bridge`.

## Claude no chat (MCP)

O serviço `mcp/` (junto da ponte, atrás do mesmo Caddy) deixa o Claude ler e alterar agenda, tarefas, notas, avisos e despertares, e agir na casa (Echo, rotinas, luzes), com login OAuth de usuário único.

1. Na VM, defina a senha de acesso: `cd bridge && docker compose run --rm -it mcp node dist/scripts/set-passphrase.js`; cole a linha `MCP_PASSPHRASE_HASH='…'` (com as aspas simples) no `bridge/.env`, junto de `MCP_PUBLIC_URL` e `MCP_JWT_SECRET` (`openssl rand -base64 48`). Veja `bridge/.env.example`.
2. Suba o serviço: `docker compose up -d mcp caddy`.
3. No claude.ai: Configurações → Conectores → **Adicionar conector personalizado** → `https://seu-dominio.duckdns.org/mcp`; digite a senha na página que abrir.
4. Revogar: apague `bridge/mcp-data/refresh.json` (refresh tokens) ou troque `MCP_JWT_SECRET` (tudo); reinicie o `mcp`.

Detalhes, segurança e lista de ferramentas: `mcp/README.md`.

## Builds
```bash
cd app
flutter build linux --release --dart-define-from-file=env.json
flutter build apk --release --dart-define-from-file=env.json
```

## Próximas fases
Veja `docs/superpowers/specs/2026-09-28-organizacional-design.md`: Claude via MCP, Google Agenda, GitHub, anexos (YouTube/PDF/docx).
