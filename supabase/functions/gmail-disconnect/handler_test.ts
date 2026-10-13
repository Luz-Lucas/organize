import { assert, assertEquals } from "jsr:@std/assert@1";
import { encryptToken } from "../_shared/gmail.ts";
import { CFG, fakeFetch, jsonRes, KEY, MemStore } from "../_shared/gmail_testutil.ts";
import { handle } from "./handler.ts";

const REVOKE = "https://oauth2.googleapis.com/revoke";
const getUserId = (jwt: string) => Promise.resolve(jwt === "jwt-u1" ? "u1" : null);
const post = (h: Record<string, string>) => new Request("https://x/functions/v1/gmail-disconnect", { method: "POST", headers: h });

async function setup() {
  const store = new MemStore();
  for (const u of ["u1", "u2"]) {
    store.accounts.set(u, { user_id: u, account_email: `${u}@g.com`, refresh_token_enc: await encryptToken(`R-${u}`, KEY), scopes: "s" });
    store.states.set(u, { status: "ok", unread_count: 4, account_email: `${u}@g.com` });
    store.items.set(u, new Map([["m", { gmail_id: "m" } as never]]));
  }
  return store;
}

Deno.test("desconectar revoga o token, apaga os dados do usuário e marca not_connected", async () => {
  const store = await setup();
  const f = fakeFetch([[REVOKE, () => jsonRes({})]]);
  const res = await handle(post({ Authorization: "Bearer jwt-u1" }), { cfg: CFG, store, fetchFn: f.fn, getUserId });
  assertEquals(await res.json(), { ok: true });

  assertEquals(new URLSearchParams(f.calls[0].body).get("token"), "R-u1");
  assertEquals(store.accounts.has("u1"), false);
  assertEquals(store.ids("u1"), []);
  assertEquals(store.states.get("u1"), {
    status: "not_connected", unread_count: 0, account_email: null, last_synced_at: null, message: null,
  });
  // outro usuário intacto
  assert(store.accounts.has("u2"));
  assertEquals(store.ids("u2"), ["m"]);
  assertEquals(store.states.get("u2")!.status, "ok");
});

Deno.test("falha ao revogar não impede apagar os dados", async () => {
  const store = await setup();
  const f = fakeFetch([[REVOKE, () => Promise.reject(new TypeError("rede"))]]);
  const res = await handle(post({ Authorization: "Bearer jwt-u1" }), { cfg: CFG, store, fetchFn: f.fn, getUserId });
  assertEquals(res.status, 200);
  await res.body?.cancel();
  assertEquals(store.accounts.has("u1"), false);
});

Deno.test("desconectar sem JWT válido => 401 e nada muda", async () => {
  const store = await setup();
  const f = fakeFetch([]);
  const res = await handle(post({}), { cfg: CFG, store, fetchFn: f.fn, getUserId });
  assertEquals(res.status, 401);
  await res.body?.cancel();
  assert(store.accounts.has("u1"));
  assertEquals(f.calls.length, 0);
});

Deno.test("desconectar NÃO revoga o token se o Drive do mesmo usuário usa o mesmo e-mail (mesmo client OAuth)", async () => {
  const store = await setup();
  store.siblings.set("u1", ["u1@g.com"]);
  const f = fakeFetch([[REVOKE, () => jsonRes({})]]);
  const res = await handle(post({ Authorization: "Bearer jwt-u1" }), { cfg: CFG, store, fetchFn: f.fn, getUserId });
  assertEquals(await res.json(), { ok: true });
  assertEquals(f.calls.length, 0);
  // os dados do Gmail saem normalmente
  assertEquals(store.accounts.has("u1"), false);
  assertEquals(store.ids("u1"), []);
  assertEquals(store.states.get("u1")!.status, "not_connected");
});

Deno.test("desconectar revoga se o Drive do usuário é de outra conta Google", async () => {
  const store = await setup();
  store.siblings.set("u1", ["outra@g.com"]);
  const f = fakeFetch([[REVOKE, () => jsonRes({})]]);
  const res = await handle(post({ Authorization: "Bearer jwt-u1" }), { cfg: CFG, store, fetchFn: f.fn, getUserId });
  assertEquals(res.status, 200);
  await res.body?.cancel();
  assertEquals(f.calls.length, 1);
});

Deno.test("se a consulta da outra conta falhar, não revoga (conservador) e ainda apaga os dados", async () => {
  const store = await setup();
  store.hasSiblingAccount = () => Promise.reject(new Error("db"));
  const f = fakeFetch([[REVOKE, () => jsonRes({})]]);
  const res = await handle(post({ Authorization: "Bearer jwt-u1" }), { cfg: CFG, store, fetchFn: f.fn, getUserId });
  assertEquals(res.status, 200);
  await res.body?.cancel();
  assertEquals(f.calls.length, 0);
  assertEquals(store.accounts.has("u1"), false);
});
