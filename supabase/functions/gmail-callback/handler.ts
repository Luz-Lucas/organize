import {
  encryptToken,
  exchangeCode,
  type FetchFn,
  getProfileEmail,
  type GmailConfig,
  type GoogleProvider,
  hasModifyScope,
  scopeGranted,
  type NonceStore,
  userAllowed,
  verifyStateFull,
} from "../_shared/gmail.ts";
import { type GmailStore, syncAccount } from "../_shared/gmail_sync.ts";
import { ensureFolder, getAboutEmail, ROOT_FOLDER_NAME, type DriveStore } from "../_shared/drive.ts";

export interface CallbackDeps {
  cfg: GmailConfig | null;
  store: GmailStore;
  /** Necessário só para o provider `drive`. */
  driveStore?: DriveStore;
  fetchFn: FetchFn;
  /** GOOGLE_ALLOWED_USER_ID: se definido, só esse usuário conecta. */
  allowedUserId?: string;
  /** Nonces do state já usados (uso único). Sem ele, o state só vale por tempo (testes). */
  nonceStore?: NonceStore;
  /** Opcional: se definido, em vez da página HTML responde 302 para `${doneUrl}?gmail=ok|error` (ou `?drive=`). */
  doneUrl?: string;
  now?: () => number;
}

const SECURITY_HEADERS = {
  "Content-Type": "text/html; charset=utf-8",
  "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'",
  "X-Frame-Options": "DENY",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
  "Cache-Control": "no-store",
};

// Textos fixos: nada vindo da requisição é refletido na página.
const TEXT: Record<GoogleProvider, { ok: string; fail: string; title: string }> = {
  gmail: {
    ok: "Gmail conectado. Pode voltar ao app.",
    fail: "Não foi possível conectar o Gmail. Volte ao app e tente de novo.",
    title: "Gmail",
  },
  drive: {
    ok: "Google Drive conectado. Pode voltar ao app.",
    fail: "Não foi possível conectar o Google Drive. Volte ao app e tente de novo.",
    title: "Google Drive",
  },
};

function page(ok: boolean, status: number, doneUrl?: string, provider: GoogleProvider = "gmail"): Response {
  if (doneUrl) {
    const u = new URL(doneUrl);
    u.searchParams.set(provider, ok ? "ok" : "error");
    return new Response(null, { status: 302, headers: { Location: u.toString(), "Cache-Control": "no-store" } });
  }
  const msg = ok ? TEXT[provider].ok : TEXT[provider].fail;
  const html = `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">` +
    `<meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex">` +
    `<title>${TEXT[provider].title}</title><style>body{font-family:system-ui,sans-serif;display:flex;min-height:100vh;margin:0;` +
    `align-items:center;justify-content:center;background:#f6f5fa;color:#1c1b22;text-align:center;padding:24px}` +
    `main{max-width:22rem}h1{font-size:1.25rem;font-weight:600}</style></head>` +
    `<body><main><h1>${msg}</h1></main></body></html>`;
  return new Response(html, { status, headers: SECURITY_HEADERS });
}

/** GET ?code&state (retorno do consentimento do Google). O provider (gmail|drive) vem no state assinado. */
export async function handle(req: Request, deps: CallbackDeps): Promise<Response> {
  const { cfg, store, fetchFn, doneUrl } = deps;
  const fail = (status = 400, provider: GoogleProvider = "gmail") => page(false, status, doneUrl, provider);
  if (req.method !== "GET") return fail(405);
  if (!cfg) return fail(500);

  const params = new URL(req.url).searchParams;
  const code = params.get("code");
  const state = params.get("state");
  // `error=access_denied` (usuário negou) cai aqui: sem code não há o que trocar.
  if (params.get("error") || !code || !state) return fail();

  const info = await verifyStateFull(state, cfg.stateSecret, deps.now?.() ?? Date.now());
  if (!info) return fail();
  const { userId, provider, nonce } = info;
  if (provider === "drive" && !deps.driveStore) return fail(500, provider);
  // Cadastro aberto: o state assinado não basta, o dono precisa ser o usuário permitido.
  if (!userAllowed(deps.allowedUserId, userId)) return fail(403, provider);
  // Uso único: o mesmo state (link de consentimento) não conecta duas vezes.
  if (deps.nonceStore) {
    let fresh = false;
    try {
      fresh = await deps.nonceStore.consume(nonce);
    } catch {
      console.error(`${provider}-callback: falha ao registrar o nonce`);
      return fail(500, provider);
    }
    if (!fresh) return fail(400, provider);
  }

  try {
    const tokens = await exchangeCode(cfg, code, fetchFn);
    if (!scopeGranted(provider, tokens.scope) || !tokens.refreshToken) return fail(400, provider);

    if (provider === "drive") {
      await connectDrive(deps.driveStore!, cfg, userId, tokens.accessToken, tokens.refreshToken, tokens.scope, fetchFn);
      return page(true, 200, doneUrl, provider);
    }

    const email = await getProfileEmail(tokens.accessToken, fetchFn);
    const row = {
      user_id: userId,
      account_email: email,
      refresh_token_enc: await encryptToken(tokens.refreshToken, cfg.tokenKey),
      scopes: tokens.scope,
    };
    await store.upsertAccount(row);
    await store.setState(userId, {
      account_email: email,
      unread_count: 0,
      can_modify: hasModifyScope(tokens.scope),
      status: "ok",
      last_synced_at: null,
      message: null,
    });
    // Primeira sincronização; nunca lança (falhas viram status no email_state).
    await syncAccount({ cfg, store, fetchFn }, row);
    return page(true, 200, doneUrl);
  } catch (e) {
    console.error(`${provider}-callback: falha`, e instanceof Error ? e.message : "interno");
    return fail(500, provider);
  }
}

/** Grava a conta (token cifrado), acha/cria a pasta raiz "Organize" e marca drive_state=ok. */
async function connectDrive(
  driveStore: DriveStore,
  cfg: GmailConfig,
  userId: string,
  accessToken: string,
  refreshToken: string,
  scopes: string,
  fetchFn: FetchFn,
): Promise<void> {
  const email = await getAboutEmail(accessToken, fetchFn);
  const root = await ensureFolder(accessToken, "root", ROOT_FOLDER_NAME, fetchFn);
  await driveStore.upsertAccount({
    user_id: userId,
    account_email: email,
    refresh_token_enc: await encryptToken(refreshToken, cfg.tokenKey),
    scopes,
  });
  await driveStore.setState(userId, {
    account_email: email,
    status: "ok",
    root_folder_id: root.id,
    message: null,
    connected_at: new Date().toISOString(),
  });
}
