import { assert, assertEquals } from "jsr:@std/assert@1";
import { encryptToken, type EmailItem } from "../_shared/gmail.ts";
import { API, type Call, CFG, fakeFetch, jsonRes, KEY, MemStore, TOKEN_URL } from "../_shared/gmail_testutil.ts";
import { type ActionDeps, handle } from "./handler.ts";

const MODIFY = "https://www.googleapis.com/auth/gmail.modify";
const METADATA = "https://www.googleapis.com/auth/gmail.metadata";
const BATCH = `${API}/messages/batchModify`;

const item = (id: string, unread: boolean): EmailItem => ({
  gmail_id: id, thread_id: null, from_name: "X", from_addr: "x@x.com", subject: "S", received_at: null, unread,
});

async function setup(scopes = MODIFY) {
  const store = new MemStore();
  for (const u of ["u1", "u2"]) {
    store.accounts.set(u, {
      user_id: u,
      account_email: `${u}@gmail.com`,
      refresh_token_enc: await encryptToken(`R-${u}`, KEY),
      scopes,
    });
    store.states.set(u, { unread_count: 5, status: "ok", account_email: `${u}@gmail.com`, can_modify: true });
  }
  store.items.set("u1", new Map([["a1", item("a1", true)], ["b2", item("b2", true)], ["c3", item("c3", false)]]));
  store.items.set("u2", new Map([["a1", item("a1", true)]])); // mesmo id em outro usuário
  return store;
}

function google(opts: { batch?: (c: Call) => Response; unread?: number | "falha"; token?: () => Response } = {}) {
  return fakeFetch([
    [TOKEN_URL, () => opts.token?.() ?? jsonRes({ access_token: "ACC" })],
    [BATCH, (c) => opts.batch?.(c) ?? new Response(null, { status: 204 })],
    [`${API}/labels/INBOX`, () =>
      opts.unread === "falha" ? jsonRes({ error: "x" }, 500) : jsonRes({ messagesUnread: opts.unread ?? 1 })],
  ]);
}

const getUserId = (jwt: string) => Promise.resolve(jwt === "jwt-u1" ? "u1" : jwt === "jwt-u2" ? "u2" : null);
const post = (body: unknown, jwt = "jwt-u1") =>
  new Request("https://x/functions/v1/gmail-action", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...(jwt ? { Authorization: `Bearer ${jwt}` } : {}) },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
const deps = (store: MemStore, fn: ActionDeps["fetchFn"], extra: Partial<ActionDeps> = {}): ActionDeps => ({
  cfg: CFG, store, fetchFn: fn, getUserId, ...extra,
});
const unreadOf = (s: MemStore, u: string, id: string) => s.items.get(u)!.get(id)!.unread;

Deno.test("mark_read: batchModify com removeLabelIds UNREAD, itens lidos e contagem do INBOX", async () => {
  const store = await setup();
  const f = google({ unread: 7 });
  const res = await handle(post({ action: "mark_read", ids: ["a1", "b2"] }), deps(store, f.fn));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { ok: true, marked: 2, unread_count: 7 });

  const batch = f.calls.find((c) => c.url === BATCH)!;
  assertEquals(batch.method, "POST");
  assertEquals(batch.headers.get("authorization"), "Bearer ACC");
  assertEquals(JSON.parse(batch.body), { ids: ["a1", "b2"], removeLabelIds: ["UNREAD"] });

  assertEquals(unreadOf(store, "u1", "a1"), false);
  assertEquals(unreadOf(store, "u1", "b2"), false);
  assertEquals(store.states.get("u1")!.unread_count, 7);
  assertEquals(store.states.get("u1")!.status, "ok");
  // outro usuário intacto, mesmo com id igual
  assertEquals(unreadOf(store, "u2", "a1"), true);
  assertEquals(store.states.get("u2")!.unread_count, 5);
});

Deno.test("mark_read remove ids repetidos antes de chamar o Google", async () => {
  const store = await setup();
  const f = google();
  await handle(post({ action: "mark_read", ids: ["a1", "a1", "b2"] }), deps(store, f.fn));
  assertEquals(JSON.parse(f.calls.find((c) => c.url === BATCH)!.body).ids, ["a1", "b2"]);
});

Deno.test("mark_all_read pega só os não lidos do usuário em email_items", async () => {
  const store = await setup();
  const f = google({ unread: 0 });
  const res = await handle(post({ action: "mark_all_read" }), deps(store, f.fn));
  assertEquals(await res.json(), { ok: true, marked: 2, unread_count: 0 });
  assertEquals(JSON.parse(f.calls.find((c) => c.url === BATCH)!.body).ids.sort(), ["a1", "b2"]);
  assertEquals(store.states.get("u1")!.unread_count, 0);
  assertEquals(unreadOf(store, "u2", "a1"), true);
});

Deno.test("mark_all_read sem nenhum não lido não chama o Google", async () => {
  const store = await setup();
  store.items.set("u1", new Map([["c3", item("c3", false)]]));
  const f = google();
  const res = await handle(post({ action: "mark_all_read" }), deps(store, f.fn));
  assertEquals(await res.json(), { ok: true, marked: 0 });
  assertEquals(f.calls.length, 0);
});

Deno.test("entrada inválida => 400, sem falar com o Google", async () => {
  const store = await setup();
  const f = google();
  const many = Array.from({ length: 101 }, (_, i) => `id${i}`);
  const bad: unknown[] = [
    {},
    { action: "apagar", ids: ["a1"] },
    { action: "mark_read" },
    { action: "mark_read", ids: [] },
    { action: "mark_read", ids: "a1" },
    { action: "mark_read", ids: many },
    { action: "mark_read", ids: ["a1", 5] },
    { action: "mark_read", ids: ["a1/../x"] },
    { action: "mark_read", ids: ["a b"] },
    { action: "mark_read", ids: ["a1?alt=x"] },
    { action: "mark_read", ids: [""] },
    { action: "mark_read", ids: ["x".repeat(65)] },
    "não é json",
    [],
  ];
  for (const b of bad) {
    const res = await handle(post(b), deps(store, f.fn));
    assertEquals(res.status, 400, JSON.stringify(b).slice(0, 60));
    await res.body?.cancel();
  }
  assertEquals(f.calls.length, 0);
  assertEquals(unreadOf(store, "u1", "a1"), true);
});

Deno.test("100 ids é o máximo aceito", async () => {
  const store = await setup();
  const f = google();
  const ids = Array.from({ length: 100 }, (_, i) => `id${i}`);
  const res = await handle(post({ action: "mark_read", ids }), deps(store, f.fn));
  assertEquals(res.status, 200);
  await res.body?.cancel();
  assertEquals(JSON.parse(f.calls.find((c) => c.url === BATCH)!.body).ids.length, 100);
});

Deno.test("autorização: método, JWT e GOOGLE_ALLOWED_USER_ID", async () => {
  const store = await setup();
  const f = google();
  const body = { action: "mark_read", ids: ["a1"] };
  const opt = await handle(new Request("https://x/", { method: "OPTIONS" }), deps(store, f.fn));
  assertEquals(opt.status, 204);
  const get = await handle(new Request("https://x/", { method: "GET" }), deps(store, f.fn));
  assertEquals(get.status, 405);
  await get.body?.cancel();
  for (const jwt of ["", "jwt-ruim"]) {
    const res = await handle(post(body, jwt), deps(store, f.fn));
    assertEquals(res.status, 401);
    await res.body?.cancel();
  }
  const forbidden = await handle(post(body, "jwt-u2"), deps(store, f.fn, { allowedUserId: "u1" }));
  assertEquals(forbidden.status, 403);
  await forbidden.body?.cancel();
  const noCfg = await handle(post(body), deps(store, f.fn, { cfg: null }));
  assertEquals(noCfg.status, 500);
  await noCfg.body?.cancel();
  assertEquals(f.calls.length, 0);
  assertEquals(unreadOf(store, "u1", "a1"), true);
});

Deno.test("sem Gmail conectado => 404 not_connected", async () => {
  const store = await setup();
  store.accounts.delete("u1");
  const f = google();
  const res = await handle(post({ action: "mark_read", ids: ["a1"] }), deps(store, f.fn));
  assertEquals(res.status, 404);
  assertEquals((await res.json()).error, "not_connected");
  assertEquals(f.calls.length, 0);
});

Deno.test("Google 403 insufficientPermissions => 409 reconnect, SEM auth_required e sem alterar itens", async () => {
  for (const body of [
    { error: { code: 403, errors: [{ reason: "insufficientPermissions" }] } },
    { error: { code: 403, status: "PERMISSION_DENIED", details: [{ reason: "ACCESS_TOKEN_SCOPE_INSUFFICIENT" }] } },
  ]) {
    const store = await setup();
    const f = google({ batch: () => jsonRes(body, 403) });
    const res = await handle(post({ action: "mark_read", ids: ["a1"] }), deps(store, f.fn));
    assertEquals(res.status, 409);
    assertEquals(await res.json(), { error: "reconnect", message: "Reconecte o Gmail para permitir marcar como lida." });
    assertEquals(store.states.get("u1")!.status, "ok");
    assertEquals(store.states.get("u1")!.unread_count, 5);
    assertEquals(unreadOf(store, "u1", "a1"), true);
  }
});

Deno.test("conta antiga (só gmail.metadata) => 409 reconnect sem chamar o Google", async () => {
  const store = await setup(METADATA);
  const f = google();
  const res = await handle(post({ action: "mark_read", ids: ["a1"] }), deps(store, f.fn));
  assertEquals(res.status, 409);
  assertEquals((await res.json()).error, "reconnect");
  assertEquals(f.calls.length, 0);
  assertEquals(store.states.get("u1")!.status, "ok");
});

Deno.test("invalid_grant ao renovar o token => auth_required (como no sync)", async () => {
  const store = await setup();
  const f = google({ token: () => jsonRes({ error: "invalid_grant" }, 400) });
  const res = await handle(post({ action: "mark_read", ids: ["a1"] }), deps(store, f.fn));
  assertEquals(res.status, 401);
  assertEquals((await res.json()).error, "auth_required");
  assertEquals(store.states.get("u1")!.status, "auth_required");
  assertEquals(store.states.get("u1")!.message, "Reconecte o Gmail.");
  assertEquals(unreadOf(store, "u1", "a1"), true);
  assertEquals(store.states.get("u2")!.status, "ok");
});

Deno.test("Google 401 no batchModify também marca auth_required", async () => {
  const store = await setup();
  const f = google({ batch: () => jsonRes({ error: { code: 401 } }, 401) });
  const res = await handle(post({ action: "mark_read", ids: ["a1"] }), deps(store, f.fn));
  assertEquals(res.status, 401);
  assertEquals(store.states.get("u1")!.status, "auth_required");
});

Deno.test("erro temporário do Google => 502 e itens inalterados", async () => {
  for (const status of [429, 503, 400]) {
    const store = await setup();
    const f = google({ batch: () => jsonRes({ error: { message: "segredo-interno" } }, status) });
    const res = await handle(post({ action: "mark_read", ids: ["a1"] }), deps(store, f.fn));
    assertEquals(res.status, 502);
    const text = JSON.stringify(await res.json());
    assert(!text.includes("segredo-interno"));
    assertEquals(unreadOf(store, "u1", "a1"), true);
    assertEquals(store.states.get("u1")!.status, "ok");
  }
});

Deno.test("falha ao ler a contagem do INBOX não desfaz: itens lidos, resposta ok sem unread_count", async () => {
  const store = await setup();
  const f = google({ unread: "falha" });
  const res = await handle(post({ action: "mark_read", ids: ["a1"] }), deps(store, f.fn));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { ok: true, marked: 1 });
  assertEquals(unreadOf(store, "u1", "a1"), false);
  assertEquals(store.states.get("u1")!.unread_count, 5); // o próximo sync corrige
});

Deno.test("nada de token, e-mail ou assunto no log", async () => {
  const store = await setup();
  const logs: string[] = [];
  const orig = console.error;
  console.error = (...a: unknown[]) => void logs.push(a.join(" "));
  try {
    const f = google({ token: () => jsonRes({ error: "invalid_grant" }, 400) });
    await (await handle(post({ action: "mark_read", ids: ["a1"] }), deps(store, f.fn))).body?.cancel();
  } finally {
    console.error = orig;
  }
  const all = logs.join("\n");
  for (const s of ["R-u1", "ACC", "u1@gmail.com", "x@x.com"]) assert(!all.includes(s));
});
