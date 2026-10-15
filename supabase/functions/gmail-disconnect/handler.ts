import { bearer, CORS, decryptToken, type FetchFn, type GmailConfig, json, revokeToken } from "../_shared/gmail.ts";
import type { GmailStore } from "../_shared/gmail_sync.ts";

export interface DisconnectDeps {
  cfg: GmailConfig | null;
  store: GmailStore;
  fetchFn: FetchFn;
  getUserId: (jwt: string) => Promise<string | null>;
}

/** POST -> { ok: true }. Revoga o token (melhor esforço) e apaga tudo do usuário. */
export async function handle(req: Request, deps: DisconnectDeps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (req.method !== "POST") return json({ error: "método não permitido" }, 405);

  const jwt = bearer(req);
  const userId = jwt ? await deps.getUserId(jwt).catch(() => null) : null;
  if (!userId) return json({ error: "não autorizado" }, 401);

  try {
    const acct = await deps.store.getAccount(userId);
    if (acct && deps.cfg) {
      // Gmail e Drive usam o mesmo client OAuth: revogar aqui derrubaria também o Drive da mesma conta Google.
      const shared = await deps.store.hasSiblingAccount(userId, acct.account_email).catch(() => true);
      if (!shared) {
        try {
          await revokeToken(await decryptToken(acct.refresh_token_enc, deps.cfg.tokenKey), deps.fetchFn);
        } catch {
          // melhor esforço: segue apagando mesmo sem revogar
        }
      }
    }
    // Estado primeiro: se algo falhar adiante, o app já mostra "não conectado".
    await deps.store.setState(userId, {
      account_email: null,
      unread_count: 0,
      can_modify: false,
      status: "not_connected",
      last_synced_at: null,
      message: null,
    });
    await deps.store.deleteItemsNotIn(userId, []);
    await deps.store.deleteAccount(userId);
    return json({ ok: true });
  } catch {
    console.error("gmail-disconnect: falha");
    return json({ error: "não foi possível desconectar" }, 500);
  }
}
