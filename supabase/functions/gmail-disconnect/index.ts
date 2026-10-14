import { loadConfig } from "../_shared/gmail.ts";
import { createAdminClient, createStore } from "../_shared/gmail_store.ts";
import { handle } from "./handler.ts";

const db = createAdminClient();
const store = createStore(db);

Deno.serve((req) =>
  handle(req, {
    cfg: loadConfig((k) => Deno.env.get(k)),
    store,
    fetchFn: fetch,
    getUserId: async (jwt) => {
      const { data, error } = await db.auth.getUser(jwt);
      return error ? null : data.user?.id ?? null;
    },
  })
);
