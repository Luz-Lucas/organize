// Utilitários só para testes: fetch falso e GmailStore em memória.
import { b64encode, type EmailItem, type FetchFn, type GmailConfig } from "./gmail.ts";
import type { AccountRow, GmailStore, StatePatch, StateRow } from "./gmail_sync.ts";

export const KEY = b64encode(new Uint8Array(32).map((_, i) => i + 1));
export const CFG: GmailConfig = {
  clientId: "cid.apps.googleusercontent.com",
  clientSecret: "segredo-do-cliente",
  tokenKey: KEY,
  stateSecret: "state-secret-de-teste",
  redirectUri: "https://proj.supabase.co/functions/v1/gmail-callback",
};

export interface Call {
  url: string;
  method: string;
  headers: Headers;
  body: string;
}

export const jsonRes = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

/** Fetch falso: o primeiro roteador cujo prefixo casa responde; senão 599 (teste falha por isso). */
export function fakeFetch(routes: [string, (call: Call) => Response | Promise<Response>][]) {
  const calls: Call[] = [];
  const fn: FetchFn = async (input, init) => {
    const req = new Request(input as string, init);
    const call: Call = { url: req.url, method: req.method, headers: req.headers, body: await req.text() };
    calls.push(call);
    for (const [prefix, h] of routes) if (call.url.startsWith(prefix)) return await h(call);
    return jsonRes({ error: "rota não prevista no teste" }, 599);
  };
  return { fn, calls };
}

export const TOKEN_URL = "https://oauth2.googleapis.com/token";
export const API = "https://gmail.googleapis.com/gmail/v1/users/me";

export function msg(id: string, opts: { from?: string; subject?: string; unread?: boolean; at?: number } = {}) {
  const headers = [];
  if (opts.from !== undefined) headers.push({ name: "From", value: opts.from });
  if (opts.subject !== undefined) headers.push({ name: "Subject", value: opts.subject });
  return {
    id,
    threadId: `t-${id}`,
    labelIds: opts.unread ? ["INBOX", "UNREAD"] : ["INBOX"],
    internalDate: String(opts.at ?? 1_760_000_000_000),
    payload: { headers },
  };
}

export class MemStore implements GmailStore {
  accounts = new Map<string, AccountRow>();
  states = new Map<string, Record<string, unknown>>();
  items = new Map<string, Map<string, EmailItem>>();

  getAccount(u: string) {
    return Promise.resolve(this.accounts.get(u) ?? null);
  }
  listAccounts() {
    return Promise.resolve([...this.accounts.values()]);
  }
  upsertAccount(r: AccountRow) {
    this.accounts.set(r.user_id, r);
    return Promise.resolve();
  }
  deleteAccount(u: string) {
    this.accounts.delete(u);
    return Promise.resolve();
  }
  getState(u: string) {
    return Promise.resolve((this.states.get(u) as unknown as StateRow | undefined) ?? null);
  }
  setState(u: string, p: StatePatch) {
    this.states.set(u, { unread_count: 0, ...this.states.get(u), ...p });
    return Promise.resolve();
  }
  upsertItems(u: string, items: EmailItem[]) {
    const m = this.items.get(u) ?? new Map();
    for (const i of items) m.set(i.gmail_id, i);
    this.items.set(u, m);
    return Promise.resolve();
  }
  deleteItemsNotIn(u: string, keep: string[]) {
    const m = this.items.get(u);
    if (m) for (const id of [...m.keys()]) if (!keep.includes(id)) m.delete(id);
    return Promise.resolve();
  }
  ids(u: string) {
    return [...(this.items.get(u)?.keys() ?? [])].sort();
  }
}
