import { bearer, CORS, json, safeEqual } from "../_shared/gmail.ts";
import { type AccountRow, type SyncDeps, syncAccount, syncAll } from "../_shared/gmail_sync.ts";

export interface SyncHandlerDeps extends Omit<SyncDeps, "cfg"> {
  cfg: SyncDeps["cfg"] | null;
  cronSecret: string | undefined;
  getUserId: (jwt: string) => Promise<string | null>;
  budgetMs?: number;
  /** Janela mínima entre sincronizações pedidas pelo próprio usuário. */
  minUserIntervalMs?: number;
}

export const DEFAULT_BUDGET_MS = 60_000;
export const DEFAULT_USER_INTERVAL_MS = 15_000;

/** POST. `x-cron-secret` => todas as contas; JWT de usuário => só a conta dele. */
export async function handle(req: Request, deps: SyncHandlerDeps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (req.method !== "POST") return json({ error: "método não permitido" }, 405);
  if (!deps.cfg) return json({ error: "serviço não configurado" }, 500);
  const syncDeps: SyncDeps = { cfg: deps.cfg, store: deps.store, fetchFn: deps.fetchFn, now: deps.now };
  const budget = deps.budgetMs ?? DEFAULT_BUDGET_MS;

  const sent = req.headers.get("x-cron-secret");
  if (sent && deps.cronSecret && await safeEqual(sent, deps.cronSecret)) {
    try {
      const accounts = await deps.store.listAccounts();
      return json(await syncAll(syncDeps, accounts, budget));
    } catch {
      console.error("gmail-sync: falha ao listar contas");
      return json({ error: "falha interna" }, 500);
    }
  }

  const jwt = bearer(req);
  const userId = jwt ? await deps.getUserId(jwt).catch(() => null) : null;
  if (!userId) return json({ error: "não autorizado" }, 401);

  try {
    const acct: AccountRow | null = await deps.store.getAccount(userId);
    if (!acct) return json({ status: "not_connected" });

    const state = await deps.store.getState(userId);
    const clock = deps.now ?? (() => new Date());
    const minGap = deps.minUserIntervalMs ?? DEFAULT_USER_INTERVAL_MS;
    if (state?.status === "ok" && state.last_synced_at) {
      if (clock().getTime() - new Date(state.last_synced_at).getTime() < minGap) {
        return json({ status: "ok", skipped: true });
      }
    }
    return json({ status: await syncAccount(syncDeps, acct) });
  } catch {
    console.error("gmail-sync: falha");
    return json({ error: "falha interna" }, 500);
  }
}
