import {
  batchMarkRead,
  bearer,
  CORS,
  decryptToken,
  type FetchFn,
  getInboxUnread,
  type GmailConfig,
  GoogleError,
  hasModifyScope,
  json,
  refreshAccessToken,
  userAllowed,
} from "../_shared/gmail.ts";
import { type GmailStore, MSG_AUTH } from "../_shared/gmail_sync.ts";

export interface ActionDeps {
  cfg: GmailConfig | null;
  store: GmailStore;
  fetchFn: FetchFn;
  getUserId: (jwt: string) => Promise<string | null>;
  /** GOOGLE_ALLOWED_USER_ID: se definido, só esse usuário age. */
  allowedUserId?: string;
}

export const MAX_IDS = 100;
const ID_RE = /^[A-Za-z0-9_-]{1,64}$/;
export const MSG_RECONNECT = "Reconecte o Gmail para permitir marcar como lida.";
const MSG_FAIL = "Não foi possível marcar como lida agora.";

/** Devolve a lista de ids (únicos) ou null se o corpo for inválido. */
function parseIds(raw: unknown): string[] | null {
  if (!Array.isArray(raw) || raw.length < 1 || raw.length > MAX_IDS) return null;
  if (!raw.every((id) => typeof id === "string" && ID_RE.test(id))) return null;
  return [...new Set(raw as string[])];
}

/**
 * POST { action: 'mark_read', ids: [gmail_id...] } | { action: 'mark_all_read' }
 * -> { ok, marked, unread_count? }. Tira o rótulo UNREAD no Gmail e reflete em email_items/email_state.
 */
export async function handle(req: Request, deps: ActionDeps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (req.method !== "POST") return json({ error: "método não permitido" }, 405);
  if (!deps.cfg) return json({ error: "serviço não configurado" }, 500);
  const { cfg, store, fetchFn } = deps;

  const jwt = bearer(req);
  const userId = jwt ? await deps.getUserId(jwt).catch(() => null) : null;
  if (!userId) return json({ error: "não autorizado" }, 401);
  if (!userAllowed(deps.allowedUserId, userId)) return json({ error: "não permitido" }, 403);

  const body = await req.json().catch(() => null) as { action?: unknown; ids?: unknown } | null;
  const action = body && typeof body === "object" ? body.action : undefined;
  let ids: string[] | null = null;
  if (action === "mark_read") {
    ids = parseIds(body!.ids);
    if (!ids) return json({ error: "ids inválidos" }, 400);
  } else if (action !== "mark_all_read") {
    return json({ error: "ação inválida" }, 400);
  }

  try {
    const acct = await store.getAccount(userId);
    if (!acct) return json({ error: "not_connected", message: "Conecte o Gmail em Ajustes." }, 404);
    // Conta conectada antes do escopo novo: nem adianta tentar.
    if (!hasModifyScope(acct.scopes)) return json({ error: "reconnect", message: MSG_RECONNECT }, 409);

    if (!ids) {
      ids = await store.listUnreadIds(userId, MAX_IDS);
      if (!ids.length) return json({ ok: true, marked: 0 });
    }

    let access: string;
    try {
      let refresh: string;
      try {
        refresh = await decryptToken(acct.refresh_token_enc, cfg.tokenKey);
      } catch {
        throw new GoogleError("auth"); // chave trocada ou dado corrompido: só reconectar resolve
      }
      access = await refreshAccessToken(cfg, refresh, fetchFn);
      await batchMarkRead(access, ids, fetchFn);
    } catch (e) {
      if (e instanceof GoogleError && e.kind === "scope") {
        // Falta permissão: não é token revogado, então NÃO marca auth_required.
        return json({ error: "reconnect", message: MSG_RECONNECT }, 409);
      }
      if (e instanceof GoogleError && e.kind === "auth") {
        await store.setState(userId, { account_email: acct.account_email, status: "auth_required", message: MSG_AUTH });
        return json({ error: "auth_required", message: MSG_AUTH }, 401);
      }
      console.error("gmail-action: falha", e instanceof GoogleError ? e.message : "interno");
      return json({ error: "google", message: MSG_FAIL }, 502);
    }

    await store.markItemsRead(userId, ids);
    // Contagem real do INBOX (como no sync). Se falhar, o próximo sync corrige.
    let unread: number | undefined;
    try {
      unread = await getInboxUnread(access, fetchFn);
      const state = await store.getState(userId);
      await store.setState(userId, { status: state?.status ?? "ok", unread_count: unread });
    } catch {
      console.error("gmail-action: não atualizou a contagem");
      unread = undefined;
    }
    return json(unread === undefined ? { ok: true, marked: ids.length } : { ok: true, marked: ids.length, unread_count: unread });
  } catch {
    console.error("gmail-action: falha");
    return json({ error: "falha interna" }, 500);
  }
}
