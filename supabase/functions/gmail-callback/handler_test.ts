import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { decryptToken, signState } from "../_shared/gmail.ts";
import { API, CFG, fakeFetch, jsonRes, KEY, MemNonceStore, MemStore, msg, TOKEN_URL } from "../_shared/gmail_testutil.ts";
import { handle } from "./handler.ts";

const SCOPE = "https://www.googleapis.com/auth/gmail.metadata"; // conta antiga
const MODIFY = "https://www.googleapis.com/auth/gmail.modify";
const U = "11111111-1111-1111-1111-111111111111";
const cb = (q: Record<string, string>) => new Request(`https://x/functions/v1/gmail-callback?${new URLSearchParams(q)}`);

function google(token: Record<string, unknown>) {
  return fakeFetch([
    [TOKEN_URL, (c) =>
      new URLSearchParams(c.body).get("grant_type") === "authorization_code"
        ? jsonRes({ access_token: "ACC", ...token })
        : jsonRes({ access_token: "ACC2" })],
    [`${API}/profile`, () => jsonRes({ emailAddress: "contato@gmail.com" })],
    [`${API}/labels/INBOX`, () => jsonRes({ messagesUnread: 5 })],
    [`${API}/messages?`, () => jsonRes({ messages: [{ id: "m1" }] })],
    [`${API}/messages/m1`, () => jsonRes(msg("m1", { from: "A <a@x.com>", subject: "Oi", unread: true }))],
  ]);
}

async function run(q: (state: string) => Record<string, string>, token: Record<string, unknown>, doneUrl?: string) {
  const store = new MemStore();
  const f = google(token);
  const state = await signState(U, CFG.stateSecret);
  const res = await handle(cb(q(state)), { cfg: CFG, store, fetchFn: f.fn, doneUrl });
  return { res, store, f, html: await res.text() };
}

Deno.test("callback feliz: guarda token cifrado, estado ok, primeira sincronização e página segura", async () => {
  const { res, store, f, html } = await run((state) => ({ code: "CODE", state }), { refresh_token: "REFRESH-X", scope: SCOPE });
  assertEquals(res.status, 200);
  assertStringIncludes(html, "Gmail conectado. Pode voltar ao app.");

  const acct = store.accounts.get(U)!;
  assertEquals(acct.account_email, "contato@gmail.com");
  assertEquals(acct.scopes, SCOPE);
  assert(!acct.refresh_token_enc.includes("REFRESH-X"));
  assertEquals(await decryptToken(acct.refresh_token_enc, KEY), "REFRESH-X");

  assertEquals(store.states.get(U)!.status, "ok");
  assertEquals(store.states.get(U)!.unread_count, 5); // primeira sincronização rodou
  assertEquals(store.ids(U), ["m1"]);

  const exchange = new URLSearchParams(f.calls.find((c) => c.url === TOKEN_URL)!.body);
  assertEquals(exchange.get("code"), "CODE");
  assertEquals(exchange.get("redirect_uri"), CFG.redirectUri);

  assertEquals(res.headers.get("content-security-policy")!.startsWith("default-src 'none'; style-src 'unsafe-inline'"), true);
  assertEquals(res.headers.get("x-frame-options"), "DENY");
  assertEquals(res.headers.get("cache-control"), "no-store");
  assertStringIncludes(res.headers.get("content-type")!, "text/html");
  assert(!html.includes("<script"));
});

function assertRejected(r: Awaited<ReturnType<typeof run>>) {
  assertEquals(r.res.status >= 400, true);
  assertStringIncludes(r.html, "Não foi possível conectar o Gmail");
  assertEquals(r.store.accounts.size, 0);
  assertEquals(r.store.states.size, 0);
}

Deno.test("callback recusa state inválido, expirado, ausente ou negado pelo usuário", async () => {
  await assertRejected(await run(() => ({ code: "CODE", state: "adulterado.abc" }), { refresh_token: "R", scope: SCOPE }));
  await assertRejected(await run(() => ({ code: "CODE" }), { refresh_token: "R", scope: SCOPE }));
  await assertRejected(await run((state) => ({ state, error: "access_denied" }), { refresh_token: "R", scope: SCOPE }));
  await assertRejected(await run((state) => ({ state }), { refresh_token: "R", scope: SCOPE }));

  const store = new MemStore();
  const f = google({ refresh_token: "R", scope: SCOPE });
  const old = await signState(U, CFG.stateSecret, Date.now() - 11 * 60_000);
  const res = await handle(cb({ code: "C", state: old }), { cfg: CFG, store, fetchFn: f.fn });
  assertEquals(res.status, 400);
  assertEquals(f.calls.length, 0); // nem chega a falar com o Google
  assertEquals(store.accounts.size, 0);
});

Deno.test("callback sem refresh_token ou sem o escopo gmail.metadata é recusado", async () => {
  await assertRejected(await run((state) => ({ code: "C", state }), { scope: SCOPE }));
  await assertRejected(await run((state) => ({ code: "C", state }), { refresh_token: "R", scope: "openid email" }));
  await assertRejected(await run((state) => ({ code: "C", state }), { refresh_token: "R" }));
  // escopo parecido não conta
  await assertRejected(await run((state) => ({ code: "C", state }), { refresh_token: "R", scope: SCOPE + ".x" }));
});

Deno.test("callback: erro do Google na troca => página genérica, sem refletir parâmetros nem detalhes", async () => {
  const store = new MemStore();
  const f = fakeFetch([[TOKEN_URL, () => jsonRes({ error: "invalid_grant", error_description: "segredo-interno" }, 400)]]);
  const state = await signState(U, CFG.stateSecret);
  const res = await handle(cb({ code: "<script>x</script>", state }), { cfg: CFG, store, fetchFn: f.fn });
  const html = await res.text();
  assertEquals(res.status >= 400, true);
  assert(!html.includes("segredo-interno") && !html.includes("<script>x"));
  assertEquals(store.accounts.size, 0);
});

Deno.test("callback com GMAIL_DONE_URL redireciona em vez de mostrar HTML", async () => {
  const ok = await run((state) => ({ code: "C", state }), { refresh_token: "R", scope: SCOPE }, "myapp://gmail");
  assertEquals(ok.res.status, 302);
  assertEquals(ok.res.headers.get("location"), "myapp://gmail?gmail=ok");
  const bad = await run(() => ({ code: "C", state: "x.y" }), { refresh_token: "R", scope: SCOPE }, "https://app.example/done");
  assertEquals(bad.res.status, 302);
  assertEquals(bad.res.headers.get("location"), "https://app.example/done?gmail=error");
});

Deno.test("callback só aceita GET", async () => {
  const res = await handle(new Request("https://x/", { method: "POST" }), { cfg: CFG, store: new MemStore(), fetchFn: fetch });
  assertEquals(res.status, 405);
  await res.body?.cancel();
});

Deno.test("callback com GOOGLE_ALLOWED_USER_ID: state de outro usuário => 403, sem falar com o Google nem gravar nada", async () => {
  const store = new MemStore();
  const f = google({ refresh_token: "R", scope: SCOPE });
  const state = await signState(U, CFG.stateSecret);
  const res = await handle(cb({ code: "C", state }), { cfg: CFG, store, fetchFn: f.fn, allowedUserId: "99999999-9999-9999-9999-999999999999" });
  assertEquals(res.status, 403);
  await res.body?.cancel();
  assertEquals(f.calls.length, 0);
  assertEquals(store.accounts.size, 0);
  assertEquals(store.states.size, 0);

  // o dono passa
  const f2 = google({ refresh_token: "R", scope: SCOPE });
  const ok = await handle(cb({ code: "C", state: await signState(U, CFG.stateSecret) }), { cfg: CFG, store, fetchFn: f2.fn, allowedUserId: U });
  assertEquals(ok.status, 200);
  await ok.body?.cancel();
  assertEquals(store.accounts.has(U), true);
});

Deno.test("callback sem GOOGLE_ALLOWED_USER_ID continua aceitando qualquer usuário (com aviso no log)", async () => {
  const warns: string[] = [];
  const orig = console.warn;
  console.warn = (...a: unknown[]) => warns.push(a.join(" "));
  try {
    const r = await run((state) => ({ code: "CODE", state }), { refresh_token: "R", scope: SCOPE });
    assertEquals(r.res.status, 200);
  } finally {
    console.warn = orig;
  }
  assertEquals(warns.some((w) => w.includes("GOOGLE_ALLOWED_USER_ID")), true);
});

Deno.test("callback: o nonce do state é de uso único (repetir o mesmo callback é recusado)", async () => {
  const store = new MemStore();
  const nonceStore = new MemNonceStore();
  const state = await signState(U, CFG.stateSecret);

  const f1 = google({ refresh_token: "R1", scope: SCOPE });
  const first = await handle(cb({ code: "C1", state }), { cfg: CFG, store, fetchFn: f1.fn, nonceStore });
  assertEquals(first.status, 200);
  await first.body?.cancel();
  assertEquals(store.accounts.has(U), true);

  const f2 = google({ refresh_token: "R2", scope: SCOPE });
  const again = await handle(cb({ code: "C2", state }), { cfg: CFG, store, fetchFn: f2.fn, nonceStore });
  assertEquals(again.status >= 400, true);
  assertStringIncludes(await again.text(), "Não foi possível conectar o Gmail");
  assertEquals(f2.calls.length, 0); // recusado antes de trocar o code
  assertEquals(await decryptToken(store.accounts.get(U)!.refresh_token_enc, KEY), "R1"); // nada foi sobrescrito
});

Deno.test("callback: falha do nonceStore (banco) recusa em vez de seguir sem a proteção", async () => {
  const store = new MemStore();
  const f = google({ refresh_token: "R", scope: SCOPE });
  const state = await signState(U, CFG.stateSecret);
  const res = await handle(cb({ code: "C", state }), {
    cfg: CFG, store, fetchFn: f.fn, nonceStore: { consume: () => Promise.reject(new Error("db")) },
  });
  assertEquals(res.status >= 400, true);
  await res.body?.cancel();
  assertEquals(f.calls.length, 0);
  assertEquals(store.accounts.size, 0);
});

Deno.test("callback com gmail.modify: aceita, guarda o escopo e marca can_modify=true", async () => {
  const { res, store } = await run((state) => ({ code: "C", state }), { refresh_token: "R", scope: `openid ${MODIFY}` });
  assertEquals(res.status, 200);
  assertEquals(store.accounts.get(U)!.scopes, `openid ${MODIFY}`);
  assertEquals(store.states.get(U)!.status, "ok");
  assertEquals(store.states.get(U)!.can_modify, true);
});

Deno.test("callback com o escopo antigo gmail.metadata continua aceito, com can_modify=false", async () => {
  const { res, store } = await run((state) => ({ code: "C", state }), { refresh_token: "R", scope: SCOPE });
  assertEquals(res.status, 200);
  assertEquals(store.states.get(U)!.status, "ok");
  assertEquals(store.states.get(U)!.can_modify, false);
});

Deno.test("callback recusa escopo gmail.modify parecido (sufixo)", async () => {
  await assertRejected(await run((state) => ({ code: "C", state }), { refresh_token: "R", scope: MODIFY + ".x" }));
});
