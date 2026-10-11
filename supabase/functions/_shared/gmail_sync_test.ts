import { assert, assertEquals } from "jsr:@std/assert@1";
import { encryptToken } from "./gmail.ts";
import { type AccountRow, syncAccount, syncAll, type SyncDeps } from "./gmail_sync.ts";
import { API, CFG, type Call, fakeFetch, jsonRes, KEY, MemStore, msg, TOKEN_URL } from "./gmail_testutil.ts";

const NOW = new Date("2026-10-16T12:00:00Z");

async function setup(userId = "u1") {
  const store = new MemStore();
  const acct: AccountRow = {
    user_id: userId,
    account_email: "contato@gmail.com",
    refresh_token_enc: await encryptToken("REFRESH-1", KEY),
    scopes: "https://www.googleapis.com/auth/gmail.metadata",
  };
  store.accounts.set(userId, acct);
  return { store, acct };
}

const deps = (store: MemStore, fn: SyncDeps["fetchFn"]): SyncDeps => ({ cfg: CFG, store, fetchFn: fn, now: () => NOW });

const tokenOk = () => jsonRes({ access_token: "ACCESS-1", expires_in: 3600 });

function gmailRoutes(ids: string[], unread: number, onTokenCall?: (c: Call) => void) {
  return fakeFetch([
    [TOKEN_URL, (c) => {
      onTokenCall?.(c);
      return tokenOk();
    }],
    [`${API}/labels/INBOX`, () => jsonRes({ id: "INBOX", messagesUnread: unread })],
    [`${API}/messages?`, () => jsonRes({ messages: ids.map((id) => ({ id, threadId: `t-${id}` })) })],
    [`${API}/messages/`, (c) => {
      const id = decodeURIComponent(new URL(c.url).pathname.split("/").pop()!);
      return jsonRes(msg(id, { from: `Remetente ${id} <${id}@x.com>`, subject: `Assunto ${id}`, unread: id !== "m2" }));
    }],
  ]);
}

Deno.test("sync feliz: itens gravados, obsoletos apagados, contagem e estado ok", async () => {
  const { store, acct } = await setup();
  store.items.set("u1", new Map([["velho", { gmail_id: "velho" } as never]]));
  store.items.set("u2", new Map([["outro-usuario", { gmail_id: "outro-usuario" } as never]]));
  const f = gmailRoutes(["m1", "m2", "m3"], 42);

  assertEquals(await syncAccount(deps(store, f.fn), acct), "ok");

  assertEquals(store.ids("u1"), ["m1", "m2", "m3"]);
  assertEquals(store.ids("u2"), ["outro-usuario"]); // não mexe em outro usuário
  assertEquals(store.items.get("u1")!.get("m1")!.from_name, "Remetente m1");
  assertEquals(store.items.get("u1")!.get("m2")!.unread, false);
  assertEquals(store.items.get("u1")!.get("m1")!.unread, true);
  assertEquals(store.states.get("u1"), {
    account_email: "contato@gmail.com",
    unread_count: 42,
    status: "ok",
    last_synced_at: NOW.toISOString(),
    message: null,
  });
});

Deno.test("sync usa só chamadas permitidas pelo escopo metadata (sem q, formato metadata)", async () => {
  const { store, acct } = await setup();
  const f = gmailRoutes(["m1"], 1);
  await syncAccount(deps(store, f.fn), acct);

  const list = f.calls.find((c) => c.url.startsWith(`${API}/messages?`))!;
  const lu = new URL(list.url);
  assertEquals(lu.searchParams.get("labelIds"), "INBOX");
  assertEquals(lu.searchParams.get("maxResults"), "15");
  assertEquals(lu.searchParams.has("q"), false);

  const get = new URL(f.calls.find((c) => c.url.startsWith(`${API}/messages/m1`))!.url);
  assertEquals(get.searchParams.get("format"), "metadata");
  assertEquals(get.searchParams.getAll("metadataHeaders"), ["From", "Subject", "Date"]);

  // refresh token decifrado vai ao Google; access token nos demais pedidos
  const tok = f.calls.find((c) => c.url === TOKEN_URL)!;
  assertEquals(new URLSearchParams(tok.body).get("refresh_token"), "REFRESH-1");
  assertEquals(new URLSearchParams(tok.body).get("grant_type"), "refresh_token");
  assertEquals(list.headers.get("authorization"), "Bearer ACCESS-1");
  assert(f.calls.every((c) => !c.url.includes("format=full") && !c.url.includes("format=raw")));
});

Deno.test("sync: caixa vazia apaga os itens e zera; mensagem que sumiu (404) é ignorada", async () => {
  const { store, acct } = await setup();
  store.items.set("u1", new Map([["velho", { gmail_id: "velho" } as never]]));
  const vazia = gmailRoutes([], 0);
  assertEquals(await syncAccount(deps(store, vazia.fn), acct), "ok");
  assertEquals(store.ids("u1"), []);

  const f = fakeFetch([
    [TOKEN_URL, tokenOk],
    [`${API}/labels/INBOX`, () => jsonRes({ messagesUnread: 2 })],
    [`${API}/messages?`, () => jsonRes({ messages: [{ id: "a1" }, { id: "gone" }] })],
    [`${API}/messages/gone`, () => jsonRes({ error: { code: 404 } }, 404)],
    [`${API}/messages/a1`, () => jsonRes(msg("a1", { from: "A <a@x.com>" }))],
  ]);
  assertEquals(await syncAccount(deps(store, f.fn), acct), "ok");
  assertEquals(store.ids("u1"), ["a1"]);
  assertEquals(store.items.get("u1")!.get("a1")!.subject, null);
});

const withItems = async () => {
  const s = await setup();
  s.store.items.set("u1", new Map([["keep", { gmail_id: "keep" } as never]]));
  s.store.states.set("u1", { unread_count: 7, status: "ok", last_synced_at: "2026-10-16T11:00:00.000Z" });
  return s;
};

Deno.test("invalid_grant no token => auth_required, itens e contagem preservados", async () => {
  const { store, acct } = await withItems();
  const f = fakeFetch([[TOKEN_URL, () => jsonRes({ error: "invalid_grant" }, 400)]]);
  assertEquals(await syncAccount(deps(store, f.fn), acct), "auth_required");
  assertEquals(store.ids("u1"), ["keep"]);
  const st = store.states.get("u1")!;
  assertEquals(st.status, "auth_required");
  assertEquals(st.unread_count, 7);
  assertEquals(st.last_synced_at, "2026-10-16T11:00:00.000Z");
  assert(typeof st.message === "string" && st.message.length > 0);
});

Deno.test("401 e 403 (não é limite de taxa) => auth_required; 403 de limite => error", async () => {
  for (const status of [401, 403]) {
    const { store, acct } = await withItems();
    const f = fakeFetch([
      [TOKEN_URL, tokenOk],
      [`${API}/labels/INBOX`, () => jsonRes({ error: { code: status } }, status)],
    ]);
    assertEquals(await syncAccount(deps(store, f.fn), acct), "auth_required");
    assertEquals(store.ids("u1"), ["keep"]);
  }
  const { store, acct } = await withItems();
  const f = fakeFetch([
    [TOKEN_URL, tokenOk],
    [`${API}/labels/INBOX`, () => jsonRes({ error: { errors: [{ reason: "userRateLimitExceeded" }] } }, 403)],
  ]);
  assertEquals(await syncAccount(deps(store, f.fn), acct), "error");
});

Deno.test("429, 5xx e falha de rede => error genérico, itens preservados", async () => {
  const cases: [string, () => Response | Promise<Response>][] = [
    ["429", () => jsonRes({}, 429)],
    ["503", () => jsonRes({}, 503)],
    ["rede", () => Promise.reject(new TypeError("falha de rede com dados@sensiveis.com"))],
  ];
  for (const [, h] of cases) {
    const { store, acct } = await withItems();
    const f = fakeFetch([[TOKEN_URL, tokenOk], [`${API}/labels/INBOX`, h]]);
    assertEquals(await syncAccount(deps(store, f.fn), acct), "error");
    assertEquals(store.ids("u1"), ["keep"]);
    const st = store.states.get("u1")!;
    assertEquals(st.status, "error");
    assertEquals(st.unread_count, 7);
    assert(!String(st.message).includes("sensiveis"));
  }
});

Deno.test("falha no token endpoint (5xx) também é error; chave errada => auth_required", async () => {
  const a = await withItems();
  const f = fakeFetch([[TOKEN_URL, () => jsonRes({}, 500)]]);
  assertEquals(await syncAccount(deps(a.store, f.fn), a.acct), "error");

  const b = await withItems();
  b.acct.refresh_token_enc = "corrompido-e-longo-o-bastante-para-passar-do-tamanho-minimo==";
  const g = fakeFetch([]);
  assertEquals(await syncAccount(deps(b.store, g.fn), b.acct), "auth_required");
  assertEquals(g.calls.length, 0);
});

Deno.test("logs não vazam assunto, endereço nem token", async () => {
  const logs: unknown[][] = [];
  const orig = console.error;
  console.error = (...a: unknown[]) => void logs.push(a);
  try {
    const { store, acct } = await withItems();
    const f = fakeFetch([
      [TOKEN_URL, tokenOk],
      [`${API}/labels/INBOX`, () => jsonRes({ error: { message: "Assunto secreto x@y.com" } }, 500)],
    ]);
    await syncAccount(deps(store, f.fn), acct);
  } finally {
    console.error = orig;
  }
  const text = JSON.stringify(logs);
  for (const s of ["secreto", "x@y.com", "REFRESH-1", "ACCESS-1"]) assert(!text.includes(s));
});

Deno.test("syncAll processa em sequência e respeita o orçamento de tempo", async () => {
  const s1 = await setup("u1");
  const s2 = await setup("u2");
  s1.store.accounts.set("u2", s2.acct);
  const f = gmailRoutes(["m1"], 1);
  let t = 0;
  const clock = () => (t += 40); // cada consulta ao relógio "gasta" 40 ms
  const out = await syncAll(deps(s1.store, f.fn), [s1.acct, s2.acct], 50, clock);
  assertEquals(out, { accounts: 2, ok: 1, auth_required: 0, error: 0, skipped: 1 });
  assertEquals(s1.store.ids("u1"), ["m1"]);
  assertEquals(s1.store.ids("u2"), []);

  const all = await syncAll(deps(s1.store, f.fn), [s1.acct, s2.acct], 60_000);
  assertEquals(all, { accounts: 2, ok: 2, auth_required: 0, error: 0, skipped: 0 });
});
