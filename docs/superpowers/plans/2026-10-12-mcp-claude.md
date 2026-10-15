# Servidor MCP para o Claude — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Servidor MCP remoto com login OAuth de usuário único que dá ao Claude (chat) acesso ao Organizacional.

**Architecture:** `mcp/` (Node 22 + TS). `src/oauth/*` + `src/http.ts` + `src/main.ts` (Task 1) expõem OAuth e montam o transporte MCP; `src/tools/*` (Task 2) registram as ferramentas num `McpServer` via `registerTools(server, ctx)`.

**Tech Stack:** Node 22, TypeScript ~7, express 4, `@modelcontextprotocol/sdk` ^1.32, zod ^4, jose ^6, `@supabase/supabase-js`, vitest ~5.

**Spec:** `docs/superpowers/specs/2026-10-12-mcp-claude-design.md` — **leia inteiro**; contém as regras de OAuth, a lista de ferramentas e a implantação.

## Global Constraints

- Textos de saída (erros, descrições das ferramentas, retornos) em **pt-BR**; identificadores de ferramentas em inglês, como no spec.
- Esqueleto já existe e compila: `mcp/package.json`, `tsconfig*.json`, `vitest.config.ts`, `src/config.ts` (`McpConfig`, `loadConfig`), `src/tools/index.ts` (`ToolContext`, `registerTools` vazio), `src/main.ts` vazio. **Não altere** `config.ts` nem a assinatura de `registerTools`/`ToolContext`; precisando de algo novo, reporte.
- **Segurança é requisito, não detalhe:** nada de segredo/senha/token/código em logs; comparação em tempo constante; PKCE S256 obrigatório; `redirect_uri` com comparação exata; erros OAuth no formato RFC 6749; sem `eval`; sem executar texto vindo de dados.
- Padrões de código: siga `bridge/` (ESM, `strict`, imports com `.js`). Comandos: `cd mcp && npx vitest run` e `npx tsc -p tsconfig.typecheck.json` devem passar.
- Subagentes **não** fazem `git commit`, **não** mexem em `bridge/`, `app/`, `supabase/`, nem nos arquivos da outra task; **não** acessam a nuvem (Supabase `--linked`, VM). Banco permitido: Supabase **local** (`npx supabase status -o env`; já rodando; migrações 20260928…20261011 aplicadas; usuário de teste local `visual@teste.local`, id em `psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -Atc "select id from auth.users where email='visual@teste.local'"`).

## Review Focus

1. Código de autorização reutilizado, expirado, ou trocado com `redirect_uri`/`client_id`/`code_verifier` errados → `invalid_grant` e **sem** emitir token (Task 1).
2. Refresh token reutilizado após rotação revoga a família (Task 1).
3. Cliente registrado com `redirect_uri` fora da lista permitida é recusado (Task 1).
4. `/mcp` sem token, com token expirado, de outro `aud` ou assinado com outro segredo → 401 com `WWW-Authenticate` correto (Task 1).
5. Toda consulta de ferramenta filtra por `user_id`: uma linha de **outro usuário** nunca aparece nem é alterada (Task 2 testa com um segundo usuário).
6. `update_task`→`done` define `completedAt`; `create_note` com título repetido (caixa/espaços diferentes) falha com mensagem clara; `append_to_note` não perde o texto existente (Task 2).
7. Evento 22:00→02:00 (atravessa a meia-noite) aceito; fim antes do início recusado (Task 2).

---

### Task 1: OAuth, transporte HTTP, main, Dockerfile e implantação

**Files:**
- Create: `mcp/src/oauth/{store.ts,pkce.ts,passphrase.ts,tokens.ts,router.ts}`, `mcp/src/http.ts` (`buildApp(cfg, deps)`), `mcp/scripts/set-passphrase.ts`, `mcp/Dockerfile`, `mcp/README.md`
- Modify: `mcp/src/main.ts`, `bridge/docker-compose.yml`, `bridge/Caddyfile`, `bridge/.env.example` (só acrescentar as 3 variáveis `MCP_*`, comentadas), `README.md` da raiz (seção "Claude no chat (MCP)")
- Test: `mcp/test/oauth.test.ts`, `mcp/test/http.test.ts`, `mcp/test/passphrase.test.ts`

**Interfaces:**
- Produces: `buildApp(cfg: McpConfig, deps: { makeServer: () => McpServer; now?: () => Date }): express.Express` — monta CORS, OAuth, `/mcp` (transporte sem sessão: a cada requisição `new McpServer(...)` via `deps.makeServer()` + `StreamableHTTPServerTransport({ sessionIdGenerator: undefined })`, `server.connect(transport)`, `transport.handleRequest(req, res, req.body)`, fechando ao terminar). `main.ts` liga `makeServer` a `new McpServer({name:'organizacional', version:'1.0.0'})` + `registerTools(server, ctx)` com `ctx = { db: createClient(cfg.supabaseUrl, cfg.serviceKey, {auth:{persistSession:false}}), userId: cfg.userId, timeZone: cfg.timeZone, now: () => new Date() }`.
- Consumes: `registerTools(server, ctx)` e `ToolContext` de `src/tools/index.ts` (Task 2 preenche).

- [x] **Step 1: Testes de OAuth (falhando)** em `test/oauth.test.ts`, subindo `buildApp` num `http.Server` em porta aleatória com `makeServer` retornando um `McpServer` com uma ferramenta `ping` de teste, `cfg` de teste (hash scrypt de uma senha de teste gerado no próprio teste com a função de `passphrase.ts`, `dataDir` = pasta temporária) e usando `fetch`. Casos: (a) `GET /.well-known/oauth-protected-resource` e `/oauth-authorization-server` com os campos do spec; (b) `POST /register` válido → `client_id`; `redirect_uris` inválido → 400 `invalid_redirect_uri`; (c) fluxo feliz completo: register → `GET /authorize` (HTML com formulário e CSRF) → `POST /authorize` com senha certa → 302 com `code` e `state` → `POST /token` com `code_verifier` → `access_token`+`refresh_token` → `POST /mcp` (`initialize` + `tools/list` pelo `Client` do SDK com `StreamableHTTPClientTransport` e header `Authorization`) lista `ping`; (d) senha errada → formulário com erro, sem redirecionar; 6ª tentativa errada do mesmo IP → 429; (e) `code_challenge_method=plain` ou sem `code_challenge` → erro; `redirect_uri` diferente do registrado → erro **sem** redirecionar; (f) trocar o mesmo `code` duas vezes → 2ª `invalid_grant`; `code_verifier` errado → `invalid_grant`; `code` expirado (relógio injetado) → `invalid_grant`; (g) refresh: troca válida devolve novo par; reuso do refresh antigo → `invalid_grant` e o refresh novo da mesma família também deixa de valer; (h) `/mcp` sem `Authorization`, com JWT expirado, `aud` errado, ou segredo errado → 401 e `WWW-Authenticate` contendo `resource_metadata="…/.well-known/oauth-protected-resource"`; (i) CORS: `Origin: https://claude.ai` recebe `Access-Control-Allow-Origin`; `Origin: https://evil.example` não; `OPTIONS` responde 204. `test/passphrase.test.ts`: `hashPassphrase`/`verifyPassphrase` ida e volta, hash com formato `scrypt$salt$hash`, senha errada falsa, hash malformado falso (nunca lança).
- [x] **Step 2:** rode e veja falhar. **Step 3:** implemente conforme o spec (`passphrase.ts`: `hashPassphrase(pass): string`, `verifyPassphrase(pass, stored): boolean` com `scryptSync` N=2^15; `pkce.ts`: `verifyS256(verifier, challenge)`; `tokens.ts`: `signAccessToken/verifyAccessToken` com `jose`; `store.ts`: clientes/códigos/refresh em memória + persistência JSON atômica em `dataDir` (escrever em arquivo temporário e `rename`; ler no start; tolerar arquivo ausente/corrompido); `router.ts`: rotas OAuth; `http.ts`: monta tudo, `app.set('trust proxy', 1)`, `express.json({limit:'1mb'})`, `express.urlencoded`). **Step 4:** testes verdes.
- [x] **Step 5:** `scripts/set-passphrase.ts`: pede a senha duas vezes **sem eco** (`readline` com `stdin` em modo raw, ou `process.stdin.setRawMode`), exige ≥ 12 caracteres e confirmação igual, imprime **somente** `MCP_PASSPHRASE_HASH=scrypt$…` (para o usuário colar no `.env`) — nunca a senha. Compila para `dist/scripts/set-passphrase.js`.
- [x] **Step 6: Implantação (arquivos, sem rodar na VM).** `Dockerfile` multi-estágio igual ao da ponte (node:22-slim, `npm ci`, `npm run build`, `npm prune --omit=dev`, `tzdata`, `ENV NODE_ENV=production TZ=America/Sao_Paulo`, `EXPOSE 8081`, `CMD ["node","dist/main.js"]`); `bridge/docker-compose.yml`: serviço `mcp` (`build: ../mcp`, `restart: unless-stopped`, `env_file: .env`, `environment: {TZ: America/Sao_Paulo, MCP_PORT: "8081", MCP_DATA_DIR: /data}`, volume `./mcp-data:/data`) e `caddy` com `depends_on`; `bridge/Caddyfile`: `@mcp path /mcp /mcp/* /.well-known/oauth-protected-resource /.well-known/oauth-authorization-server /authorize /token /register /revoke` → `reverse_proxy @mcp mcp:8081`, o resto `reverse_proxy bridge:8080` (use `handle`/`route` corretos; valide a sintaxe com `docker run --rm -v $PWD/Caddyfile:/etc/caddy/Caddyfile:ro -e DOMAIN=example.com caddy:2 caddy validate --config /etc/caddy/Caddyfile`). `README.md` do `mcp/` e a seção na raiz: como adicionar o conector (claude.ai → Configurações → Conectores → "Adicionar conector personalizado" → URL `https://seu-dominio.duckdns.org/mcp`), como definir a senha (`docker compose run --rm -it mcp node dist/scripts/set-passphrase.js` na VM), como revogar acessos, e a lista de ferramentas.
- [x] **Step 7:** `npx vitest run` + typecheck + `npm run build` verdes; `docker build -t organizacional-mcp:test .` na pasta `mcp/` compila.

### Task 2: Ferramentas MCP e acesso a dados

**Files:**
- Create: `mcp/src/tools/{agenda.ts,tasks.ts,notes.ts,study.ts,notices.ts,news.ts,alexa.ts,wake.ts,util.ts}`
- Modify: `mcp/src/tools/index.ts` (só o corpo de `registerTools`, chamando um `register*` por arquivo; mantenha `ToolContext` e a assinatura)
- Test: `mcp/test/tools.test.ts` (+ `mcp/test/helpers.ts` com a criação do cliente MCP em memória e dos usuários de teste)

**Interfaces:** consome `ToolContext` (`db`, `userId`, `timeZone`, `now`). Cada `registerX(server: McpServer, ctx: ToolContext): void` usa `server.registerTool(name, { title, description, inputSchema (zod raw shape), annotations }, handler)` do SDK real instalado (**leia** `node_modules/@modelcontextprotocol/sdk/dist/esm/server/mcp.d.ts` para a assinatura exata desta versão e `types.d.ts` para `ToolAnnotations`). Handlers devolvem `{ content: [{ type: 'text', text: JSON.stringify(obj) }] }` e, em erro de uso (validação, não encontrado, título duplicado), `{ isError: true, content: [{ type:'text', text:'<mensagem em pt-BR>' }] }` — nunca lançam exceção para o cliente nem vazam mensagem interna do banco.

- [x] **Step 1: Leia o esquema real** das tabelas em `supabase/migrations/*.sql` (`events`, `tasks`, `notes`, `spaces`, `notices`, `user_settings`, `news_*` e a função `news_feed`, `alexa_commands`, `alexa_devices`, `alexa_routines`, `wake_plans`) e das regras em `app/lib/domain/*.dart` (`normalizeTitle`, wikilinks, `TaskItem.moved`) para reproduzir as mesmas regras (título único de nota por usuário sem diferenciar caixa/espaços; `completedAt`; fim ≥ início).
- [x] **Step 2: Testes (falhando)** `test/tools.test.ts`: requer `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` (use `describe.skipIf`); cria **dois usuários de teste** pela API admin do Auth local (e-mails aleatórios `mcp-a-<rand>@teste.local` / `mcp-b-…`) e apaga ambos no `afterAll` (cascata limpa os dados); cliente MCP em memória (`InMemoryTransport.createLinkedPair()` do SDK) conectado a um `McpServer` com `registerTools` do usuário A. Cobrir os itens 5–7 do **Review Focus** e: `create_event` + `list_agenda` (22:00→02:00 aparece nos dois dias; fim<início → `isError`), `update_task` doing→done→todo (`completedAt` define/limpa), `list_tasks` ordem doing→todo→prazo, `create_note` duplicada (`"Redes"` vs `" redes "`) → `isError`, `append_to_note` mantém o corpo e acrescenta com linha em branco, `search_notes` sem acento/caixa, `create_study_plan` (nota + N tarefas com prazos crescentes; `weeks`≤12, `sessionsPerWeek`≤7), avisos (`create_notice` → `list_notices` → `archive_notice` some), `list_news`/`create_news_digest` (semeie 3 itens em `news_items` com fonte; digest cria nota "Notícias — dd/MM/yyyy"), `upsert_wake_plan`/`list_wake_plans`, ferramentas Alexa: `alexa_speak` insere em `alexa_commands` (`kind:'speak'`, payload com `echoDeviceId` e `text`) e, sem ponte respondendo, devolve `status:"pending"` após o tempo limite (injete `waitMs` curto via parâmetro opcional do registrador, padrão 20 000); com um "robô de ponte" de teste que atualiza o comando para `done`, devolve `done`; `alexa_device` valida ação e brilho 0–100; **isolamento**: dados criados pelo usuário B (evento, tarefa, nota, aviso) não aparecem para A e `update_*`/`delete_*` de um id de B retornam `isError` sem alterar nada.
- [x] **Step 3:** rode e veja falhar. **Step 4:** implemente (`util.ts`: `ok(obj)`, `fail(msg)`, `parseWhen(str, tz)` aceitando ISO com/sem offset (sem offset = fuso do usuário), `clampLimit`, `normalizeTitle`; cada ferramenta com `.eq('user_id', ctx.userId)` em **todas** as leituras, atualizações e remoções, e `user_id` explícito em todas as inserções). **Step 5:** testes verdes, typecheck limpo.
- [x] **Step 6:** relatório: lista final de ferramentas (nome, anotação), decisões onde o spec estava aberto, e qualquer divergência.

---

### Task 3 (coordenador): Integração, implantação e verificação

- [x] `npm run build`, suíte, `docker build`; revisão de código independente (foco em OAuth e isolamento por usuário); commit; implantar na VM (imagem, `.env` com `MCP_PUBLIC_URL`/`MCP_JWT_SECRET`, Caddyfile, `docker compose up -d`); verificar de fora os metadados, o 401 com `WWW-Authenticate` e o `/health` da ponte; o usuário define a senha (`set-passphrase`) e adiciona o conector no claude.ai.
