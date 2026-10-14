import { createAdminClient } from "../_shared/gmail_store.ts";
import { handle } from "./handler.ts";

const db = createAdminClient();

const repos = (Deno.env.get("GITHUB_REPOS") ?? "")
  .split(",")
  .map((r) => r.trim())
  .filter(Boolean);

Deno.serve((req) =>
  handle(req, {
    token: Deno.env.get("GITHUB_TOKEN") || null,
    allowedUserId: Deno.env.get("GITHUB_ALLOWED_USER_ID") || null,
    repos,
    getUserId: async (jwt) => {
      const { data, error } = await db.auth.getUser(jwt);
      return error ? null : data.user?.id ?? null;
    },
    fetch: (input, init) => fetch(input, init),
  })
);
