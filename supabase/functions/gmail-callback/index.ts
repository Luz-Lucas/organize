import { loadConfig } from "../_shared/gmail.ts";
import { createDriveStore } from "../_shared/drive_store.ts";
import { createAdminClient, createStore } from "../_shared/gmail_store.ts";
import { handle } from "./handler.ts";

const db = createAdminClient();
const store = createStore(db);
const driveStore = createDriveStore(db);

// Atende o redirect do Gmail e do Drive (o provider vem no `state` assinado).
Deno.serve((req) =>
  handle(req, {
    cfg: loadConfig((k) => Deno.env.get(k)),
    store,
    driveStore,
    fetchFn: fetch,
    doneUrl: Deno.env.get("GMAIL_DONE_URL") || undefined,
  })
);
