# Servidor MCP para o Claude (claude.ai, desktop e celular) — Design

**Data:** 2026-10-12 · Aprovado pelo usuário no chat (plano Claude Pro). Corresponde à "Fase 4" do roadmap original.

## Objetivo

Permitir que o Claude, no chat normal, **leia e altere** o Organizacional (agenda, tarefas, notas, avisos, despertares) e **aja na casa** (falar no Echo, rotinas, luzes), com login seguro de usuário único.

## Decisões

| Tema | Decisão |
|---|---|
| Hospedagem | Novo serviço Node 22 + TypeScript em `mcp/`, na mesma VM Oracle, atrás do Caddy já existente, no mesmo domínio: `https://seu-dominio.duckdns.org` (rotas `/mcp`, `/.well-known/oauth-*`, `/authorize`, `/token`, `/register`, `/revoke`). O resto continua indo para a ponte. |
| Protocolo | MCP **Streamable HTTP**, modo **sem sessão** (um transporte por requisição), via `@modelcontextprotocol/sdk` ^1.32. |
| Login | **OAuth 2.1 mínimo, um único usuário**: metadados RFC 9728 (`oauth-protected-resource`) e RFC 8414 (`oauth-authorization-server`), registro dinâmico de clientes (RFC 7591), `authorization_code` com **PKCE S256 obrigatório**, `refresh_token` com rotação. A página `/authorize` pede a **senha de acesso** (hash scrypt na VM). Sem senha, ninguém conecta. |
| Dados | Supabase com a chave `service_role` e `ORGANIZACIONAL_USER_ID` (mesmo modelo da ponte): **toda consulta filtra por `user_id`**. |
| Alexa | O servidor **não** fala com a Amazon: insere em `alexa_commands` (como o app) e espera o resultado por até ~20 s; a ponte executa. |
| Segurança das ferramentas | Anotações MCP: leitura = `readOnlyHint`; apagar/agir na casa = `destructiveHint` (o Claude pede confirmação). Textos vindos de fora (manchetes, eventos importados) são devolvidos como **dados**. Sem ferramenta para apagar notas. |

## OAuth — regras

- `POST /register`: aceita só `redirect_uris` que casem com `McpConfig.allowedRedirects` (padrão: `https://claude.ai/api/mcp/auth_callback`, `https://claude.com/api/mcp/auth_callback`, loopback `http://localhost|127.0.0.1[:porta]/…`); `token_endpoint_auth_method: "none"`; máximo 50 clientes; grava em `<dataDir>/clients.json`; devolve `client_id` aleatório.
- `GET /authorize`: exige `response_type=code`, `client_id` registrado, `redirect_uri` **idêntico** a um registrado, `code_challenge` com `code_challenge_method=S256`, `state` opcional repassado. Mostra formulário (senha) com token CSRF; cabeçalhos `X-Frame-Options: DENY`, `Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; form-action 'self'`, `Cache-Control: no-store`.
- `POST /authorize`: confere CSRF e senha (`crypto.scryptSync` + `timingSafeEqual`); **limite de tentativas** (5 por 15 min por IP e 20 por hora no total; excedeu → 429 e mensagem); sucesso → código aleatório de 32 bytes (base64url), validade **5 min**, uso único, preso a `client_id`+`redirect_uri`+`code_challenge`; redireciona com `code` e `state`.
- `POST /token`: `authorization_code` (confere PKCE, `client_id`, `redirect_uri`, código não usado/expirado) → `access_token` (JWT HS256, `iss`=publicUrl, `aud`=`<publicUrl>/mcp`, `sub`=userId, validade **1 h**) + `refresh_token` (32 bytes aleatórios, validade **30 dias**, guardado como sha256 em `<dataDir>/refresh.json`, **rotaciona a cada uso**; reuso de um refresh já trocado revoga a família). `refresh_token` → novo par. Erros no formato OAuth (`invalid_grant`, `invalid_client`, `invalid_request`).
- `POST /revoke` (RFC 7009): revoga um refresh token. Script `npm run revoke-all` não é necessário: trocar `MCP_JWT_SECRET` invalida os acessos e apagar `refresh.json` invalida os refresh tokens.
- `POST|GET|DELETE /mcp`: exige `Authorization: Bearer <jwt>` válido (assinatura, `exp`, `iss`, `aud`, `sub`=userId). Falha → **401** com `WWW-Authenticate: Bearer resource_metadata="<publicUrl>/.well-known/oauth-protected-resource"`. CORS: `Access-Control-Allow-Origin` só para `https://claude.ai` e `https://claude.com` nos endpoints OAuth/metadados e `/mcp`; `OPTIONS` respondido.
- Corpo JSON limitado a 1 MB; `trust proxy` ligado (atrás do Caddy) para o IP real; logs sem tokens, senhas ou códigos.

## Ferramentas (nomes em inglês; textos e retornos em pt-BR)

Todas retornam JSON (texto) com campos em camelCase; datas em ISO 8601 **com fuso** (`America/Sao_Paulo`); listas com limite padrão 50 e máximo 200. Entradas validadas com zod (títulos 1–200 caracteres; notas até 100 000).

| Ferramenta | O que faz | Anotação |
|---|---|---|
| `list_agenda` | Eventos entre `from` e `to` (padrão hoje a +7 dias), com tarefas atrasadas/do dia opcionais | leitura |
| `create_event` / `update_event` | Cria/edita (`title`, `startsAt`, `endsAt`, `location`, `allDay`); fim ≥ início | escrita |
| `delete_event` | Apaga por id | destrutiva |
| `list_tasks` | Filtra por `status` (todo/doing/done), `dueBefore`, `spaceId`; ordena doing→todo, prazo | leitura |
| `create_task` / `update_task` | Cria/edita; `update_task` move de status (done define `completedAt`, sair de done limpa) | escrita |
| `delete_task` | Apaga | destrutiva |
| `search_notes` | Busca por título/corpo (sem acento/caixa); devolve id, título, trecho; `get` opcional por id/título com corpo completo | leitura |
| `create_note` / `append_to_note` | Cria (título único, sem diferenciar caixa/espaços) / acrescenta texto ao fim; `[[links]]` preservados | escrita |
| `create_study_plan` | Cria uma nota de plano + série de tarefas com prazos (`subject`, `startDate`, `topics[]`, `sessionsPerWeek`, `weeks`); retorna ids | escrita |
| `list_notices` / `create_notice` / `archive_notice` | Quadro de avisos | leitura / escrita |
| `list_news` | Manchetes via função SQL `news_feed` (as mesmas regras do app) | leitura |
| `create_news_digest` | Cria a nota "Notícias — dd/MM/yyyy" com as manchetes | escrita |
| `list_alexa_devices` / `list_alexa_routines` | Dispositivos (não ocultos) e rotinas sincronizados | leitura |
| `alexa_speak` | Fala um texto num Echo (`echoDeviceId`) | destrutiva* |
| `alexa_run_routine` | Executa uma rotina | destrutiva* |
| `alexa_device` | `turnOn`/`turnOff`/`setBrightness` num dispositivo | destrutiva* |
| `list_wake_plans` / `upsert_wake_plan` | Despertares (campos da tabela `wake_plans`) | leitura / escrita |

\* "destrutiva" no sentido MCP de "age no mundo real": o Claude pede confirmação.

Comandos Alexa: `insert into alexa_commands (user_id, kind, payload)` com `kind` ∈ `speak`, `routine`, `device`; espera `status` final por até 20 s (poll a cada 1 s); devolve `{status, result}` ou `{status:"pending", note:"a ponte ainda não respondeu"}`.

## Implantação

- `mcp/Dockerfile` (multi-estágio, como a ponte), serviço `mcp` no `bridge/docker-compose.yml` (`env_file: .env`, volume `./mcp-data:/data`, `MCP_PORT=8081`); `bridge/Caddyfile` roteia os caminhos do MCP/OAuth para `mcp:8081` e o resto para `bridge:8080`.
- Variáveis novas no `.env` da VM: `MCP_PUBLIC_URL`, `MCP_JWT_SECRET` (gerado), `MCP_PASSPHRASE_HASH` (gerado pelo `scripts/set-passphrase.ts`, que o **usuário** roda na VM; eu nunca vejo a senha).
- A imagem é compilada no PC e enviada com `docker save | docker load` (a VM tem 1 GB).

## Testes e verificação

Testes de fluxo OAuth completo em memória (registro → authorize → token → /mcp) com **todos os casos negativos**; testes das ferramentas contra o Supabase **local** (`SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY`/`TEST_USER_ID`; pulam sem elas); cliente MCP de teste (SDK) listando e chamando ferramentas por HTTP; `tsc` limpo. Fora do alcance de teste automático: a conexão real do claude.ai (o usuário conecta ao adicionar o conector).
