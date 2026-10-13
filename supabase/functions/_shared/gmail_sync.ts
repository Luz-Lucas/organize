// Sincronização de um usuário: lê o INBOX (cabeçalhos) e grava email_state/email_items.
// A lógica fala com o banco só pela interface GmailStore (a implementação real fica em
// gmail_store.ts), o que permite testar sem rede nem banco.

import {
  decryptToken,
  type EmailItem,
  type FetchFn,
  getInboxUnread,
  getMessageMeta,
  GoogleError,
  hasModifyScope,
  type GmailConfig,
  INBOX_LIMIT,
  listInboxIds,
  refreshAccessToken,
} from "./gmail.ts";

export interface AccountRow {
  user_id: string;
  account_email: string;
  refresh_token_enc: string;
  scopes: string;
}

export type EmailStatus = "not_connected" | "ok" | "auth_required" | "error";

export interface StatePatch {
  account_email?: string | null;
  unread_count?: number;
  /** A conta tem gmail.modify (pode marcar como lida)? */
  can_modify?: boolean;
  status: EmailStatus;
  last_synced_at?: string | null;
  message?: string | null;
}

export interface StateRow {
  status: EmailStatus;
  last_synced_at: string | null;
}

export interface GmailStore {
  getAccount(userId: string): Promise<AccountRow | null>;
  listAccounts(): Promise<AccountRow[]>;
  upsertAccount(row: AccountRow): Promise<void>;
  deleteAccount(userId: string): Promise<void>;
  /** Existe outra linha de google_accounts do usuário (outro provider) com o mesmo account_email? */
  hasSiblingAccount(userId: string, accountEmail: string): Promise<boolean>;
  getState(userId: string): Promise<StateRow | null>;
  /** Upsert parcial: só as colunas presentes no patch são alteradas. */
  setState(userId: string, patch: StatePatch): Promise<void>;
  upsertItems(userId: string, items: EmailItem[]): Promise<void>;
  /** Apaga as linhas do usuário cujo gmail_id não está em keepIds (vazio = apaga todas). */
  deleteItemsNotIn(userId: string, keepIds: string[]): Promise<void>;
  /** gmail_id das mensagens não lidas do usuário (no máximo `limit`). */
  listUnreadIds(userId: string, limit: number): Promise<string[]>;
  /** unread=false nas mensagens do usuário com esses ids. */
  markItemsRead(userId: string, ids: string[]): Promise<void>;
}

export const MSG_AUTH = "Reconecte o Gmail.";
export const MSG_ERROR = "Não foi possível atualizar o Gmail agora.";
const FETCH_CONCURRENCY = 5;

export interface SyncDeps {
  cfg: GmailConfig;
  store: GmailStore;
  fetchFn: FetchFn;
  now?: () => Date;
}

export type SyncResult = "ok" | "auth_required" | "error";

/** Sincroniza uma conta. Nunca lança: o resultado vai para email_state. */
export async function syncAccount(deps: SyncDeps, acct: AccountRow): Promise<SyncResult> {
  const { cfg, store, fetchFn } = deps;
  const now = deps.now ?? (() => new Date());
  try {
    let refresh: string;
    try {
      refresh = await decryptToken(acct.refresh_token_enc, cfg.tokenKey);
    } catch {
      throw new GoogleError("auth"); // chave trocada ou dado corrompido: só reconectar resolve
    }
    const access = await refreshAccessToken(cfg, refresh, fetchFn);
    const unread = await getInboxUnread(access, fetchFn);
    const ids = await listInboxIds(access, fetchFn, INBOX_LIMIT);

    const items: EmailItem[] = [];
    for (let i = 0; i < ids.length; i += FETCH_CONCURRENCY) {
      const batch = await Promise.all(ids.slice(i, i + FETCH_CONCURRENCY).map((id) => getMessageMeta(access, id, fetchFn)));
      for (const m of batch) if (m) items.push(m);
    }

    if (items.length) await store.upsertItems(acct.user_id, items);
    await store.deleteItemsNotIn(acct.user_id, items.map((m) => m.gmail_id));
    await store.setState(acct.user_id, {
      account_email: acct.account_email,
      unread_count: unread,
      can_modify: hasModifyScope(acct.scopes),
      status: "ok",
      last_synced_at: now().toISOString(),
      message: null,
    });
    return "ok";
  } catch (e) {
    const auth = e instanceof GoogleError && (e.kind === "auth" || e.kind === "scope");
    // Só o tipo do erro vai para o log; nada de conteúdo de e-mail, endereço ou token.
    console.error("gmail-sync: falha", e instanceof GoogleError ? e.message : "interno");
    try {
      await store.setState(acct.user_id, {
        account_email: acct.account_email,
        status: auth ? "auth_required" : "error",
        message: auth ? MSG_AUTH : MSG_ERROR,
      });
    } catch {
      console.error("gmail-sync: não gravou o estado");
    }
    return auth ? "auth_required" : "error";
  }
}

export interface RunSummary {
  accounts: number;
  ok: number;
  auth_required: number;
  error: number;
  skipped: number;
}

/** Processa as contas em sequência, parando quando o orçamento de tempo acaba. */
export async function syncAll(
  deps: SyncDeps,
  accounts: AccountRow[],
  budgetMs: number,
  clock: () => number = Date.now,
): Promise<RunSummary> {
  const start = clock();
  const out: RunSummary = { accounts: accounts.length, ok: 0, auth_required: 0, error: 0, skipped: 0 };
  for (const acct of accounts) {
    if (clock() - start >= budgetMs) {
      out.skipped++;
      continue;
    }
    out[await syncAccount(deps, acct)]++;
  }
  return out;
}
