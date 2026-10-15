import { assertEquals } from "jsr:@std/assert@1";
import { encryptToken } from "../_shared/gmail.ts";
import { API, CFG, fakeFetch, jsonRes, KEY, MemStore, msg, TOKEN_URL } from "../_shared/gmail_testutil.ts";
import { handle, type SyncHandlerDeps } from "./handler.ts";

const NOW = new Date("2026-10-16T12:00:00Z");

async function setup() {
  const store = new MemStore();
  for (const u of ["u1", "u2"]) {
    store.accounts.set(u, {
      user_id: u,
      account_email: `${u}@gmail.com`,
      refresh_token_enc: await encryptToken(`R-${u}`, KEY),
      scopes: "s",
    });
  }
  const f = fakeFetch([
    [TOKEN_URL, () => jsonRes({ access_token: "A" })],
    [`${API}/labels/INBOX`, () => jsonRes({ messagesUnread: 3 })],
    [`${API}/messages?`, () => jsonRes({ messages: [{ id: "m1" }] })],
    [`${API}/messages/m1`, () => jsonRes(msg("m1", { from: "A <a@x.com>" }))],
  ]);
  const deps: SyncHandlerDeps = {
    cfg: CFG,
    store,
    fetchFn: f.fn,
    now: () => NOW,
    cronSecret: "cron-s3",
    getUserId: (jwt) => Promise.resolve(jwt === "jwt-u1" ? "u1" : null),
  };
  return { store, f, deps };
}
const post = (headers: Record<string, string>) => new Request("https://x/functions/v1/gmail-sync", { method: "POST", headers, body: "{}" });

Deno.test("cron (x-cron-secret) sincroniza todas as contas", async () => {
  const { store, deps } = await setup();
  const res = await handle(post({ "x-cron-secret": "cron-s3" }), deps);
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { accounts: 2, ok: 2, auth_required: 0, error: 0, skipped: 0 });
  assertEquals(store.ids("u1"), ["m1"]);
  assertEquals(store.ids("u2"), ["m1"]);
});

Deno.test("JWT de usuário sincroniza só a conta dele", async () => {
  const { store, deps } = await setup();
  const res = await handle(post({ Authorization: "Bearer jwt-u1" }), deps);
  assertEquals(await res.json(), { status: "ok" });
  assertEquals(store.ids("u1"), ["m1"]);
  assertEquals(store.ids("u2"), []);
});

Deno.test("sincronização pedida pelo usuário repetida em poucos segundos é pulada", async () => {
  const { f, deps } = await setup();
  await (await handle(post({ Authorization: "Bearer jwt-u1" }), deps)).json();
  const n = f.calls.length;
  const again = await handle(post({ Authorization: "Bearer jwt-u1" }), deps);
  assertEquals(await again.json(), { status: "ok", skipped: true });
  assertEquals(f.calls.length, n);
});

Deno.test("usuário sem conta conectada recebe not_connected", async () => {
  const { store, deps } = await setup();
  store.accounts.delete("u1");
  const res = await handle(post({ Authorization: "Bearer jwt-u1" }), deps);
  assertEquals(await res.json(), { status: "not_connected" });
});

Deno.test("sem credenciais, segredo errado ou JWT inválido => 401 e nada é sincronizado", async () => {
  const { f, deps } = await setup();
  for (const h of [{}, { "x-cron-secret": "errado" }, { Authorization: "Bearer jwt-ruim" }] as Record<string, string>[]) {
    const res = await handle(post(h), deps);
    assertEquals(res.status, 401);
    await res.body?.cancel();
  }
  const semSegredoConfigurado = await handle(post({ "x-cron-secret": "" }), { ...deps, cronSecret: "" });
  assertEquals(semSegredoConfigurado.status, 401);
  await semSegredoConfigurado.body?.cancel();
  assertEquals(f.calls.length, 0);
});

Deno.test("sync: GET => 405", async () => {
  const { deps } = await setup();
  const res = await handle(new Request("https://x/", { method: "GET" }), deps);
  assertEquals(res.status, 405);
  await res.body?.cancel();
});
