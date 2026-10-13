// Implementação de GmailStore sobre o supabase-js com a service role.
import { createClient } from "npm:@supabase/supabase-js@2";
import { siblingMatches } from "./gmail.ts";
import type { AccountRow, GmailStore, StatePatch, StateRow } from "./gmail_sync.ts";

export function createAdminClient() {
  return createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
}

type Db = ReturnType<typeof createAdminClient>;

const fail = (what: string) => new Error(`db:${what}`); // sem detalhes do erro (podem conter dados)

export function createStore(db: Db): GmailStore {
  return {
    async getAccount(userId) {
      const { data, error } = await db
        .from("google_accounts")
        .select("user_id, account_email, refresh_token_enc, scopes")
        .eq("user_id", userId)
        .eq("provider", "gmail")
        .maybeSingle();
      if (error) throw fail("getAccount");
      return (data as AccountRow | null) ?? null;
    },
    async hasSiblingAccount(userId, accountEmail) {
      const { data, error } = await db
        .from("google_accounts")
        .select("account_email")
        .eq("user_id", userId)
        .neq("provider", "gmail");
      if (error) throw fail("hasSiblingAccount");
      return siblingMatches(data as { account_email: string }[] | null, accountEmail);
    },
    async listAccounts() {
      const { data, error } = await db
        .from("google_accounts")
        .select("user_id, account_email, refresh_token_enc, scopes")
        .eq("provider", "gmail");
      if (error) throw fail("listAccounts");
      return (data as AccountRow[]) ?? [];
    },
    async upsertAccount(row) {
      const { error } = await db
        .from("google_accounts")
        .upsert({ ...row, provider: "gmail", connected_at: new Date().toISOString() }, { onConflict: "user_id,provider" });
      if (error) throw fail("upsertAccount");
    },
    async deleteAccount(userId) {
      const { error } = await db.from("google_accounts").delete().eq("user_id", userId).eq("provider", "gmail");
      if (error) throw fail("deleteAccount");
    },
    async getState(userId): Promise<StateRow | null> {
      const { data, error } = await db
        .from("email_state")
        .select("status, last_synced_at")
        .eq("user_id", userId)
        .maybeSingle();
      if (error) throw fail("getState");
      return (data as StateRow | null) ?? null;
    },
    async setState(userId, patch: StatePatch) {
      const { error } = await db.from("email_state").upsert({ user_id: userId, ...patch }, { onConflict: "user_id" });
      if (error) throw fail("setState");
    },
    async upsertItems(userId, items) {
      const rows = items.map((m) => ({ user_id: userId, ...m }));
      const { error } = await db.from("email_items").upsert(rows, { onConflict: "user_id,gmail_id" });
      if (error) throw fail("upsertItems");
    },
    async deleteItemsNotIn(userId, keepIds) {
      let q = db.from("email_items").delete().eq("user_id", userId);
      const safe = keepIds.filter((id) => /^[A-Za-z0-9_-]+$/.test(id));
      if (safe.length) q = q.not("gmail_id", "in", `(${safe.join(",")})`);
      const { error } = await q;
      if (error) throw fail("deleteItems");
    },
  };
}
