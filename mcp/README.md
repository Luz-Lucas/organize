# Servidor MCP do Organizacional

Servidor MCP remoto (Streamable HTTP, sem sessão) com login OAuth 2.1 de usuário único, para o Claude (claude.ai, desktop e celular) ler e alterar o Organizacional. Roda na mesma VM da ponte, atrás do Caddy, no mesmo domínio. Design: `docs/superpowers/specs/2026-10-12-mcp-claude-design.md`.

## Variáveis (`bridge/.env` na VM)

| Variável | Descrição |
|---|---|
| `MCP_PUBLIC_URL` | URL pública sem barra final, ex.: `https://seu-dominio.duckdns.org` |
| `MCP_JWT_SECRET` | Segredo (>= 32 caracteres) que assina os tokens: `openssl rand -base64 48` |
| `MCP_PASSPHRASE_HASH` | Hash scrypt da senha de acesso (veja abaixo) |
| `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `ORGANIZACIONAL_USER_ID` | Os mesmos da ponte |
| `MCP_ALLOWED_REDIRECTS` | (opcional) regexes extras, separadas por vírgula, para `redirect_uri` |

`MCP_PORT` (8081) e `MCP_DATA_DIR` (`/data`) já são definidos no `docker-compose.yml`.

## Definir a senha de acesso

Na VM (o terminal precisa ser interativo; a senha não aparece nem é gravada):

```bash
cd ~/organizacional/bridge
docker compose run --rm -it mcp node dist/scripts/set-passphrase.js
```

O script imprime só uma linha `MCP_PASSPHRASE_HASH='scrypt$…'`. Cole-a no `bridge/.env` **mantendo as aspas simples** (o `docker compose` interpreta `$` em arquivos `env_file`; sem as aspas o hash é corrompido). Mínimo de 12 caracteres. Depois: `docker compose up -d mcp`.

## Adicionar o conector no Claude

claude.ai → Configurações → Conectores → **Adicionar conector personalizado** → URL `https://seu-dominio.duckdns.org/mcp`. O Claude abre a página de login do servidor: digite a senha de acesso. O conector fica disponível também no desktop e no celular da mesma conta.

## Revogar acessos

- Um aplicativo/dispositivo: o Claude chama `/revoke` ao desconectar o conector.
- Todos os refresh tokens: apague `bridge/mcp-data/refresh.json` e reinicie o serviço.
- Tudo, inclusive tokens de acesso em uso (1 h): troque `MCP_JWT_SECRET` e reinicie.
- Trocar a senha: gere outro hash e reinicie; sessões existentes continuam até revogar como acima.

## Segurança (resumo)

PKCE S256 obrigatório; `redirect_uri` com comparação exata contra o registrado, e o registro só aceita padrões da lista permitida; códigos de uso único, 5 min; refresh com rotação e revogação da família no reuso; senha com scrypt e comparação em tempo constante; no máximo 5 senhas erradas por IP em 15 min e 20 por hora no total; CORS só para `https://claude.ai` e `https://claude.com`; nada de senha/token/código em logs.

## Ferramentas

`list_agenda`, `create_event`, `update_event`, `delete_event`, `list_tasks`, `create_task`, `update_task`, `delete_task`, `search_notes`, `create_note`, `append_to_note`, `create_study_plan`, `list_notices`, `create_notice`, `archive_notice`, `list_news`, `create_news_digest`, `list_alexa_devices`, `list_alexa_routines`, `alexa_speak`, `alexa_run_routine`, `alexa_device`, `list_wake_plans`, `upsert_wake_plan`. Leitura = `readOnlyHint`; apagar/agir na casa = `destructiveHint` (o Claude pede confirmação).

## Desenvolvimento

```bash
cd mcp
npm install
npx vitest run               # testes (as de ferramentas usam o Supabase local)
npx tsc -p tsconfig.typecheck.json
npm run build
docker build -t organizacional-mcp .
```

A imagem é compilada no PC e enviada para a VM com `docker save | ssh … docker load` (a VM tem 1 GB).
