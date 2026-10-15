import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { decryptToken, signState } from "../_shared/gmail.ts";
import { CFG, fakeFetch, jsonRes, KEY, MemNonceStore, MemStore, TOKEN_URL } from "../_shared/gmail_testutil.ts";
import { DRIVE, MemDriveStore } from "../_shared/drive_testutil.ts";
import { handle } from "./handler.ts";

const DRIVE_SCOPE = "https://www.googleapis.com/auth/drive";
const U = "11111111-1111-1111-1111-111111111111";
const cb = (q: Record<string, string>) => new Request(`https://x/functions/v1/gmail-callback?${new URLSearchParams(q)}`);

function google(token: Record<string, unknown>, existingRoot?: string) {
  return fakeFetch([
    [TOKEN_URL, () => jsonRes({ access_token: "ACC", ...token })],
    [`${DRIVE}/about`, () => jsonRes({ user: { emailAddress: "sua-conta@gmail.com" } })],
    [`${DRIVE}/files?q=`, () => jsonRes({ files: existingRoot ? [{ id: existingRoot, name: "Organizacional", mimeType: "application/vnd.google-apps.folder" }] : [] })],
    [`${DRIVE}/files?fields=`, () => jsonRes({ id: "NOVA-RAIZ", name: "Organizacional", mimeType: "application/vnd.google-apps.folder" })],
  ]);
}

async function run(token: Record<string, unknown>, opts: { existingRoot?: string; drive?: boolean; doneUrl?: string } = {}) {
  const store = new MemStore();
  const driveStore = new MemDriveStore();
  const f = google(token, opts.existingRoot);
  const state = await signState(U, CFG.stateSecret, Date.now(), undefined, "drive");
  const res = await handle(cb({ code: "CODE", state }), {
    cfg: CFG,
    store,
    fetchFn: f.fn,
    driveStore: opts.drive === false ? undefined : driveStore,
    doneUrl: opts.doneUrl,
  });
  return { res, store, driveStore, f, html: await res.text() };
}

Deno.test("callback do drive: guarda token cifrado, cria a pasta Organizacional e marca ok", async () => {
  const { res, store, driveStore, f, html } = await run({ refresh_token: "REFRESH-D", scope: DRIVE_SCOPE });
  assertEquals(res.status, 200);
  assertStringIncludes(html, "Google Drive conectado. Pode voltar ao app.");

  const acct = driveStore.accounts.get(U)!;
  assertEquals(acct.account_email, "sua-conta@gmail.com");
  assertEquals(acct.scopes, DRIVE_SCOPE);
  assert(!acct.refresh_token_enc.includes("REFRESH-D"));
  assertEquals(await decryptToken(acct.refresh_token_enc, KEY), "REFRESH-D");

  assertEquals(driveStore.states.get(U)?.status, "ok");
  assertEquals(driveStore.states.get(U)?.root_folder_id, "NOVA-RAIZ");
  assertEquals(driveStore.states.get(U)?.account_email, "sua-conta@gmail.com");

  const create = f.calls.find((c) => c.method === "POST" && c.url.startsWith(`${DRIVE}/files`))!;
  const body = JSON.parse(create.body);
  assertEquals(body.name, "Organizacional");
  assertEquals(body.parents, ["root"]);
  assertEquals(body.mimeType, "application/vnd.google-apps.folder");
  // nada do Gmail foi tocado
  assertEquals(store.accounts.size, 0);
  assertEquals(store.states.size, 0);
});

Deno.test("callback do drive reaproveita a pasta Organizacional que já existe", async () => {
  const { driveStore, f } = await run({ refresh_token: "R", scope: DRIVE_SCOPE }, { existingRoot: "PASTA-ANTIGA" });
  assertEquals(driveStore.states.get(U)?.root_folder_id, "PASTA-ANTIGA");
  assertEquals(f.calls.filter((c) => c.method === "POST" && c.url.startsWith(`${DRIVE}/files`)).length, 0);
});

Deno.test("callback do drive recusa sem refresh_token ou sem o escopo drive e não grava nada", async () => {
  for (const tok of [{ scope: DRIVE_SCOPE }, { refresh_token: "R", scope: "https://www.googleapis.com/auth/gmail.metadata" }]) {
    const r = await run(tok);
    assertEquals(r.res.status >= 400, true);
    assertStringIncludes(r.html, "Não foi possível conectar o Google Drive");
    assertEquals(r.driveStore.accounts.size, 0);
    assertEquals(r.driveStore.states.size, 0);
    assertEquals(r.store.accounts.size, 0);
  }
});

Deno.test("callback do drive sem driveStore configurado => 500 e nada gravado", async () => {
  const r = await run({ refresh_token: "R", scope: DRIVE_SCOPE }, { drive: false });
  assertEquals(r.res.status, 500);
  assertEquals(r.f.calls.length, 0);
});

Deno.test("callback do drive com doneUrl redireciona com ?drive=ok", async () => {
  const r = await run({ refresh_token: "R", scope: DRIVE_SCOPE }, { doneUrl: "https://app.example/volta" });
  assertEquals(r.res.status, 302);
  assertEquals(r.res.headers.get("location"), "https://app.example/volta?drive=ok");
});

Deno.test("state do gmail com escopo drive no token NÃO grava drive (e vice-versa o escopo gmail é exigido)", async () => {
  const store = new MemStore();
  const driveStore = new MemDriveStore();
  const f = google({ refresh_token: "R", scope: DRIVE_SCOPE });
  const state = await signState(U, CFG.stateSecret); // gmail
  const res = await handle(cb({ code: "C", state }), { cfg: CFG, store, fetchFn: f.fn, driveStore });
  assertEquals(res.status >= 400, true);
  await res.body?.cancel();
  assertEquals(driveStore.accounts.size, 0);
  assertEquals(store.accounts.size, 0);
});

Deno.test("callback do drive também respeita GOOGLE_ALLOWED_USER_ID e o nonce de uso único", async () => {
  const mk = async () => {
    const driveStore = new MemDriveStore();
    const f = google({ refresh_token: "R", scope: DRIVE_SCOPE });
    return { driveStore, f };
  };
  const state = await signState(U, CFG.stateSecret, Date.now(), undefined, "drive");

  const a = await mk();
  const denied = await handle(cb({ code: "C", state }), { cfg: CFG, store: new MemStore(), fetchFn: a.f.fn, driveStore: a.driveStore, allowedUserId: "99999999-9999-9999-9999-999999999999" });
  assertEquals(denied.status, 403);
  await denied.body?.cancel();
  assertEquals(a.f.calls.length, 0);
  assertEquals(a.driveStore.accounts.size, 0);

  const nonceStore = new MemNonceStore();
  const b = await mk();
  const ok = await handle(cb({ code: "C", state }), { cfg: CFG, store: new MemStore(), fetchFn: b.f.fn, driveStore: b.driveStore, allowedUserId: U, nonceStore });
  assertEquals(ok.status, 200);
  await ok.body?.cancel();
  const c = await mk();
  const replay = await handle(cb({ code: "C", state }), { cfg: CFG, store: new MemStore(), fetchFn: c.f.fn, driveStore: c.driveStore, allowedUserId: U, nonceStore });
  assertEquals(replay.status >= 400, true);
  await replay.body?.cancel();
  assertEquals(c.f.calls.length, 0);
});
