# GitHub (issues pelo app) — passo a passo de configuração

O app lista, cria, fecha/reabre e comenta issues dos seus repositórios (Mais → GitHub) e cria uma
issue a partir de uma tarefa. O token do GitHub fica **só** nos segredos da Edge Function `github`;
nunca vai ao app. Nada aqui custa dinheiro.

## 1. Criar o token fine-grained

1. GitHub → **Settings → Developer settings → Personal access tokens → Fine-grained tokens →
   Generate new token**.
2. **Token name**: `organizacional`. **Expiration**: 1 ano (anote para renovar).
3. **Repository access**: **Only select repositories** e marque só os repositórios que o app deve ver.
4. **Permissions → Repository permissions**:
   - **Issues**: Read and write
   - **Metadata**: Read-only (já vem marcada)
   Nenhuma outra permissão (nada de Contents, Pull requests etc.).
5. **Generate token** e copie o valor (`github_pat_...`). Ele só aparece uma vez.

## 2. Descobrir o seu user id do Supabase

Painel do Supabase → **Authentication → Users** → copie o **UID** da sua conta. Só esse usuário
consegue usar a função; qualquer outro recebe 403. Sem `GITHUB_ALLOWED_USER_ID` a função recusa tudo
(500 "GitHub não configurado").

## 3. Gravar os segredos e publicar

```bash
npx supabase secrets set GITHUB_TOKEN=github_pat_... GITHUB_ALLOWED_USER_ID=<uuid>
# opcional: restringe a estes repositórios (owner/repo separados por vírgula);
# sem isso, usa os repositórios que o token enxerga
npx supabase secrets set GITHUB_REPOS=seu-usuario/organizacional,seu-usuario/outro
npx supabase functions deploy github
```

`verify_jwt = true` está em `supabase/config.toml`: a função só responde a quem está logado no app.

## 4. Testar

No app: **Mais → GitHub**. Sem token a tela mostra "GitHub não configurado" e lembra estes passos.
Testes automatizados: `cd supabase/functions && deno test github`.

## Renovação e revogação

- Antes de o token expirar, gere outro igual e rode de novo o `secrets set GITHUB_TOKEN=...`.
- Para cortar o acesso na hora, revogue o token no GitHub (Settings → Developer settings).
