import {
  encryptToken,
  exchangeCode,
  type FetchFn,
  getProfileEmail,
  type GmailConfig,
  GMAIL_SCOPE,
  verifyState,
} from "../_shared/gmail.ts";
import { type GmailStore, syncAccount } from "../_shared/gmail_sync.ts";

export interface CallbackDeps {
  cfg: GmailConfig | null;
  store: GmailStore;
  fetchFn: FetchFn;
  /** Opcional: se definido, em vez da página HTML responde 302 para `${doneUrl}?gmail=ok|error`. */
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
const OK_MSG = "Gmail conectado. Pode voltar ao app.";
const FAIL_MSG = "Não foi possível conectar o Gmail. Volte ao app e tente de novo.";

function page(ok: boolean, status: number, doneUrl?: string): Response {
  if (doneUrl) {
    const u = new URL(doneUrl);
    u.searchParams.set("gmail", ok ? "ok" : "error");
    return new Response(null, { status: 302, headers: { Location: u.toString(), "Cache-Control": "no-store" } });
  }
  const msg = ok ? OK_MSG : FAIL_MSG;
  const html = `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">` +
    `<meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex">` +
    `<title>Gmail</title><style>body{font-family:system-ui,sans-serif;display:flex;min-height:100vh;margin:0;` +
    `align-items:center;justify-content:center;background:#f6f5fa;color:#1c1b22;text-align:center;padding:24px}` +
    `main{max-width:22rem}h1{font-size:1.25rem;font-weight:600}</style></head>` +
    `<body><main><h1>${msg}</h1></main></body></html>`;
  return new Response(html, { status, headers: SECURITY_HEADERS });
}

/** GET ?code&state (retorno do consentimento do Google). */
export async function handle(req: Request, deps: CallbackDeps): Promise<Response> {
  const { cfg, store, fetchFn, doneUrl } = deps;
  const fail = (status = 400) => page(false, status, doneUrl);
  if (req.method !== "GET") return fail(405);
  if (!cfg) return fail(500);

  const params = new URL(req.url).searchParams;
  const code = params.get("code");
  const state = params.get("state");
  // `error=access_denied` (usuário negou) cai aqui: sem code não há o que trocar.
  if (params.get("error") || !code || !state) return fail();

  const userId = await verifyState(state, cfg.stateSecret, deps.now?.() ?? Date.now());
  if (!userId) return fail();

  try {
    const tokens = await exchangeCode(cfg, code, fetchFn);
    if (!tokens.scope.split(/\s+/).includes(GMAIL_SCOPE) || !tokens.refreshToken) return fail();

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
      status: "ok",
      last_synced_at: null,
      message: null,
    });
    // Primeira sincronização; nunca lança (falhas viram status no email_state).
    await syncAccount({ cfg, store, fetchFn }, row);
    return page(true, 200, doneUrl);
  } catch (e) {
    console.error("gmail-callback: falha", e instanceof Error ? e.message : "interno");
    return fail(500);
  }
}
