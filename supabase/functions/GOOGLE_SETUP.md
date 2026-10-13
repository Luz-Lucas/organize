# Google (Gmail e Drive) — passo a passo de configuração

O mesmo projeto do Google Cloud e o **mesmo cliente OAuth** servem aos dois recursos:

- **Gmail (somente leitura):** o app mostra a contagem de não lidos e as últimas mensagens (remetente,
  assunto, data) do Gmail `seu-contato@exemplo.com`. Escopo `gmail.metadata` (só cabeçalhos: nunca
  corpo nem anexos).
- **Google Drive (Documentos):** o app navega, renomeia, move, compartilha e envia arquivos na conta
  `sua-conta@exemplo.com`. Escopo `https://www.googleapis.com/auth/drive` (o Drive inteiro: pastas
  existentes, mover, compartilhar). Cria a pasta **Organizacional** no Meu Drive; os arquivos importados
  do celular ficam em `Organizacional/Importados`.

Nada aqui custa dinheiro. O Drive precisa só de três passos a mais (marcados com **[Drive]**): ativar a
Drive API (1.2), adicionar o escopo (1.3, passo 5) e conectar pelo app (item 5). Os segredos, o redirect URI
e as funções `gmail-connect`/`gmail-callback` são os mesmos.

Projeto Supabase: `dgarojxettnppcahedvk`. Redirect URI usado em tudo abaixo:

```
https://dgarojxettnppcahedvk.supabase.co/functions/v1/gmail-callback
```

## 1. Google Cloud Console

Acesse https://console.cloud.google.com/ com a conta `seu-contato@exemplo.com`.

### 1.1 Criar o projeto
1. No seletor de projetos (topo da página), clique em **Novo projeto**.
2. Nome: `Organizacional` (qualquer nome serve). Local: "Sem organização". Clique em **Criar** e
   selecione o projeto criado.

### 1.2 Ativar a Gmail API e a Drive API
1. Menu **APIs e serviços → Biblioteca**.
2. Busque **Gmail API**, abra e clique em **Ativar**.
3. **[Drive]** Busque **Google Drive API**, abra e clique em **Ativar**.

### 1.3 Tela de consentimento OAuth
(O console novo chama de **Google Auth Platform**; o antigo, de "Tela de permissão OAuth".)

1. Menu **APIs e serviços → Tela de permissão OAuth** (ou **Google Auth Platform**) → **Vamos começar**.
2. **Informações do app**: nome `Organizacional`; e-mail de suporte do usuário
   `seu-contato@exemplo.com`. Avançar.
3. **Público-alvo**: escolha **Externo**. Avançar.
4. **Informações de contato**: `seu-contato@exemplo.com`. Avançar, aceite a política e **Criar**.
5. **Acesso a dados** (Data Access) → **Adicionar ou remover escopos**. Em "Adicionar escopos
   manualmente", cole:
   ```
   https://www.googleapis.com/auth/gmail.metadata
   https://www.googleapis.com/auth/drive
   ```
   (**[Drive]** o segundo é o do Drive; se o console o marcar como "restrito", é esperado.) Clique em
   **Adicionar à tabela**, depois **Atualizar** e **Salvar**. Não adicione nenhum outro escopo.
6. **Público-alvo** (Audience) → **Publicar app** → **Confirmar**. O status deve mudar para
   **Em produção**.

   Por que publicar: enquanto o app está em "Teste", o Google expira o refresh token em **7 dias** e
   a sincronização pararia toda semana. Em produção o token não expira por tempo.

### 1.4 Aviso "app não verificado" (esperado)
Como o app é pessoal e não passou pela verificação do Google, na hora de conectar aparece
"O Google não verificou este app". É normal e seguro, porque o app é seu. Para continuar:
1. Clique em **Avançado** (ou "Mostrar detalhes").
2. Clique em **Acessar Organizacional (não seguro)**.
3. Confira o pedido: no Gmail é só "Ver metadados de e-mail, como rótulos e cabeçalhos, mas não o corpo";
   no Drive é "Ver, editar, criar e excluir todos os seus arquivos do Google Drive". Clique em **Continuar**.

Não é preciso pedir verificação ao Google. Apps não verificados têm limite de 100 usuários, o que
não afeta uso pessoal.

### 1.5 Criar o cliente OAuth
1. **APIs e serviços → Credenciais** (ou **Google Auth Platform → Clientes**) →
   **Criar credenciais → ID do cliente OAuth** (**Criar cliente**).
2. Tipo de aplicativo: **Aplicativo da Web**. Nome: `Organizacional Supabase`.
3. Em **URIs de redirecionamento autorizados**, clique em **Adicionar URI** e cole exatamente:
   ```
   https://dgarojxettnppcahedvk.supabase.co/functions/v1/gmail-callback
   ```
   Não preencha "Origens JavaScript autorizadas". Clique em **Criar**.
4. Copie o **ID do cliente** e a **chave secreta do cliente**. Guarde-os só no seu gerenciador de
   senhas e nunca em arquivos do repositório.

## 2. Banco de dados (migração e segredo do cron)

Aplicação das migrações `20261016000000_gmail.sql`, `20261019000000_google_drive.sql` (tabela `drive_state`
e provider `drive` em `google_accounts`) e `20261020000000_oauth_nonce.sql` (tabela `oauth_state_nonces` e
função `consume_oauth_nonce`: cada `state` do OAuth só conecta uma vez) no projeto na nuvem (só quando você
decidir). **Aplique a migração `20261020000000` antes de publicar a nova `gmail-callback`**; sem a tabela, o
callback recusa a conexão por segurança:

```bash
npx supabase db push
```

O job `gmail-sync` (a cada 10 minutos) lê dois segredos do Vault: `cron_secret` (o mesmo do
`news-fetch`, já existe) e `gmail_sync_url`. Crie o segundo no SQL Editor do Supabase:

```sql
select vault.create_secret('https://dgarojxettnppcahedvk.supabase.co/functions/v1/gmail-sync', 'gmail_sync_url');
```

## 3. Segredos das Edge Functions

Gere os dois segredos locais e defina tudo de uma vez (troque os dois primeiros valores):

```bash
GMAIL_TOKEN_KEY="$(openssl rand -base64 32)"
STATE_SECRET="$(openssl rand -hex 32)"

npx supabase secrets set \
  GOOGLE_CLIENT_ID='COLE_O_ID_DO_CLIENTE' \
  GOOGLE_CLIENT_SECRET='COLE_A_CHAVE_SECRETA' \
  GMAIL_TOKEN_KEY="$GMAIL_TOKEN_KEY" \
  STATE_SECRET="$STATE_SECRET" \
  --project-ref dgarojxettnppcahedvk
```

- `GMAIL_TOKEN_KEY` (AES-256-GCM) cifra o refresh token no banco. **Guarde uma cópia no gerenciador
  de senhas**: se for perdida ou trocada, os tokens guardados ficam ilegíveis e basta reconectar o
  Gmail (o app mostrará "Reconecte o Gmail").
- `STATE_SECRET` assina o parâmetro `state` do OAuth (validade de 10 minutos).
- `CRON_SECRET` já existe (usado pelo `news-fetch`). Confira com
  `npx supabase secrets list --project-ref dgarojxettnppcahedvk`.
- `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` são fornecidos pela plataforma.
- `GOOGLE_ALLOWED_USER_ID` (recomendado): o cadastro do Supabase é aberto, então qualquer pessoa que
  criar uma conta poderia tentar conectar o Google. Com este segredo definido, `gmail-connect` e
  `gmail-callback` respondem 403 para qualquer outro usuário. O valor é o **UUID do seu usuário no
  Supabase** (Dashboard → Authentication → Users → coluna *User UID*):
  ```bash
  npx supabase secrets set GOOGLE_ALLOWED_USER_ID='UUID_DO_SEU_USUARIO' --project-ref dgarojxettnppcahedvk
  ```
  Sem o segredo, tudo continua funcionando como antes (qualquer usuário autenticado pode conectar) e
  o log das funções registra o aviso `GOOGLE_ALLOWED_USER_ID não definido`.
- Opcional, `GMAIL_DONE_URL`: se definido, o callback redireciona (302) para
  `<GMAIL_DONE_URL>?gmail=ok` (ou `?gmail=error`) em vez de mostrar a página HTML. Veja a nota
  abaixo.

> Nota sobre a página final: no domínio `*.supabase.co` o Supabase entrega respostas `text/html`
> das Edge Functions como texto puro, então o navegador pode mostrar o HTML como código em vez da
> página. A conexão funciona do mesmo jeito (os dados já foram gravados); só a tela final fica feia.
> Se isso acontecer, defina `GMAIL_DONE_URL` com um link do app (deep link) ou de uma página sua e
> o callback passa a redirecionar para lá.

## 4. Publicar as funções

```bash
npx supabase functions deploy gmail-connect    --project-ref dgarojxettnppcahedvk
npx supabase functions deploy gmail-callback   --project-ref dgarojxettnppcahedvk --no-verify-jwt
npx supabase functions deploy drive            --project-ref dgarojxettnppcahedvk
npx supabase functions deploy gmail-sync       --project-ref dgarojxettnppcahedvk --no-verify-jwt
npx supabase functions deploy gmail-disconnect --project-ref dgarojxettnppcahedvk
```

- `gmail-callback` não tem JWT porque quem chama é o Google (a segurança é o `state` assinado). Ele atende
  Gmail **e** Drive: o `state` assinado carrega o serviço (`gmail` ou `drive`). **[Drive]** `drive` usa o JWT
  do usuário e só responde ao dono da conta conectada; o token do Google nunca vai ao app.
- `gmail-sync` não tem JWT no gateway porque o cron envia `x-cron-secret`; a própria função exige
  esse segredo **ou** um JWT de usuário válido (e então sincroniza só a conta daquele usuário).

## 5. Conectar e testar

**[Drive]** Em **Ajustes → Documentos → Conectar Google Drive**: o app chama `gmail-connect` com
`{provider: 'drive'}` e abre a URL no navegador. Entre com `sua-conta@exemplo.com`, passe pelo aviso
"não verificado" (1.4) e aceite. Ao voltar ao app, **Mais → Documentos** mostra a pasta *Organizacional*.

Gmail:

1. No app, toque em conectar o Gmail: o app chama `gmail-connect` e abre a URL devolvida no navegador.
2. Entre com `seu-contato@exemplo.com`, passe pelo aviso "não verificado" (item 1.4) e aceite.
3. O navegador mostra "Gmail conectado. Pode voltar ao app." e a primeira sincronização já roda.
4. Teste manual do cron (use o valor real de `CRON_SECRET`):
   ```bash
   curl -s -X POST https://dgarojxettnppcahedvk.supabase.co/functions/v1/gmail-sync \
     -H 'x-cron-secret: SEU_CRON_SECRET' -H 'Content-Type: application/json' -d '{}'
   ```
   Resposta esperada: `{"accounts":1,"ok":1,"auth_required":0,"error":0,"skipped":0}`.

## 6. Desconectar / revogar

- Pelo app: a função `gmail-disconnect` revoga o token no Google e apaga as linhas do banco.
  Gmail e Drive usam o mesmo cliente OAuth: se os dois estiverem conectados na **mesma conta Google**,
  desconectar um apaga só os dados dele e **não revoga** o acesso no Google (senão o outro cairia junto);
  o acesso só é revogado ao desconectar o último.
  **[Drive]** Em Ajustes → Documentos → Desconectar (ação `disconnect` da função `drive`); os arquivos
  continuam no seu Drive.
- Pelo Google: https://myaccount.google.com/permissions → Organizacional → **Remover acesso**.
  Na próxima sincronização o app passa a mostrar "Reconecte o Gmail".

## 7. Problemas comuns

| Sintoma | Causa provável |
| --- | --- |
| Google mostra `redirect_uri_mismatch` | O URI no cliente OAuth difere do item 1.5, inclusive barra no final. |
| Google mostra `access_blocked` / "app não concluiu a verificação" | O app ainda está em "Teste" e sua conta não está como usuário de teste: publique (item 1.3, passo 6). |
| Precisa reconectar toda semana | O app ficou em "Teste": publique em produção. |
| Documentos mostra "O acesso ao Google Drive expirou" | Mesmo motivo do Gmail abaixo: reconecte em Ajustes → Documentos. |
| Google mostra `access_denied` / escopo não permitido ao conectar o Drive | O escopo `drive` não foi adicionado em 1.3 ou a Drive API não foi ativada em 1.2. |
| App mostra "Reconecte o Gmail" | Token revogado, `GMAIL_TOKEN_KEY` trocada ou senha da conta alterada: conecte de novo. |
| App mostra "Não foi possível atualizar o Gmail agora" | Erro temporário do Google (limite de taxa ou indisponibilidade); tenta de novo sozinho em 10 minutos. |

## 8. Compartilhar do celular para o Organizacional (Samsung Notes e qualquer app)

Nada a configurar no Google. No Samsung Notes: abra a nota → **Compartilhar → Organizacional** (texto vira
uma nota) ou **Salvar como PDF** e compartilhe o PDF (vai ao Drive em `Organizacional/Importados`, com uma
nota contendo o link). Para enviar arquivos é preciso ter o Drive conectado. Não existe API do Samsung
Notes: o app não lê arquivos `.sdocx`.
