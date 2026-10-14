// Utilitários só para testes do Drive: DriveStore em memória e respostas-padrão do Google.
import { encryptToken } from "./gmail.ts";
import type { DriveAccountRow, DriveStatePatch, DriveStateRow, DriveStore } from "./drive.ts";
import { KEY } from "./gmail_testutil.ts";

export const DRIVE = "https://www.googleapis.com/drive/v3";
export const UPLOAD = "https://www.googleapis.com/upload/drive/v3";

export class MemDriveStore implements DriveStore {
  accounts = new Map<string, DriveAccountRow>();
  states = new Map<string, DriveStatePatch & { user_id: string }>();
  /** E-mails de contas de OUTRO provider (Gmail) do mesmo usuário, simulando a outra linha de google_accounts. */
  siblings = new Map<string, string[]>();

  hasSiblingAccount(u: string, email: string) {
    return Promise.resolve((this.siblings.get(u) ?? []).some((e) => e.toLowerCase() === email.toLowerCase()));
  }

  getAccount(u: string) {
    return Promise.resolve(this.accounts.get(u) ?? null);
  }
  upsertAccount(r: DriveAccountRow) {
    this.accounts.set(r.user_id, r);
    return Promise.resolve();
  }
  deleteAccount(u: string) {
    this.accounts.delete(u);
    return Promise.resolve();
  }
  getState(u: string) {
    return Promise.resolve((this.states.get(u) as unknown as DriveStateRow | undefined) ?? null);
  }
  setState(u: string, p: DriveStatePatch) {
    this.states.set(u, { ...this.states.get(u), ...p, user_id: u });
    return Promise.resolve();
  }
}

export async function connectedStore(users: string[] = ["u1"], rootFolderId = "ROOT-U"): Promise<MemDriveStore> {
  const store = new MemDriveStore();
  for (const u of users) {
    store.accounts.set(u, {
      user_id: u,
      account_email: `${u}@g.com`,
      refresh_token_enc: await encryptToken(`R-${u}`, KEY),
      scopes: "https://www.googleapis.com/auth/drive",
    });
    store.states.set(u, { user_id: u, status: "ok", root_folder_id: `${rootFolderId}-${u}`, account_email: `${u}@g.com` });
  }
  return store;
}
