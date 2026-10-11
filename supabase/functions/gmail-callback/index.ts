import { loadConfig } from "../_shared/gmail.ts";
import { createAdminClient, createStore } from "../_shared/gmail_store.ts";
import { handle } from "./handler.ts";

const store = createStore(createAdminClient());

Deno.serve((req) =>
  handle(req, {
    cfg: loadConfig((k) => Deno.env.get(k)),
    store,
    fetchFn: fetch,
    doneUrl: Deno.env.get("GMAIL_DONE_URL") || undefined,
  })
);
