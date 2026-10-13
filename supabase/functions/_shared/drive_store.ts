// Implementação de DriveStore sobre o supabase-js com a service role.
import type { createAdminClient } from "./gmail_store.ts";
import type { DriveAccountRow, DriveStatePatch, DriveStateRow, DriveStore } from "./drive.ts";

type Db = ReturnType<typeof createAdminClient>;

const fail = (what: string) => new Error(`db:${what}`); // sem detalhes do erro (podem conter dados)

export function createDriveStore(db: Db): DriveStore {
  return {
    async getAccount(userId): Promise<DriveAccountRow | null> {
      const { data, error } = await db
        .from("google_accounts")
        .select("user_id, account_email, refresh_token_enc, scopes")
        .eq("user_id", userId)
        .eq("provider", "drive")
        .maybeSingle();
      if (error) throw fail("getAccount");
      return (data as DriveAccountRow | null) ?? null;
    },
    async upsertAccount(row) {
      const { error } = await db
        .from("google_accounts")
        .upsert({ ...row, provider: "drive", connected_at: new Date().toISOString() }, { onConflict: "user_id,provider" });
      if (error) throw fail("upsertAccount");
    },
    async deleteAccount(userId) {
      const { error } = await db.from("google_accounts").delete().eq("user_id", userId).eq("provider", "drive");
      if (error) throw fail("deleteAccount");
    },
    async getState(userId): Promise<DriveStateRow | null> {
      const { data, error } = await db
        .from("drive_state")
        .select("status, root_folder_id, account_email")
        .eq("user_id", userId)
        .maybeSingle();
      if (error) throw fail("getState");
      return (data as DriveStateRow | null) ?? null;
    },
    async setState(userId, patch: DriveStatePatch) {
      const { error } = await db.from("drive_state").upsert({ user_id: userId, ...patch }, { onConflict: "user_id" });
      if (error) throw fail("setState");
    },
  };
}
