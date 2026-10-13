import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { encryptToken } from "../_shared/gmail.ts";
import { CFG, fakeFetch, jsonRes, KEY, TOKEN_URL, type Call } from "../_shared/gmail_testutil.ts";
import { connectedStore, DRIVE, UPLOAD } from "../_shared/drive_testutil.ts";
import { handle } from "./handler.ts";

const REVOKE = "https://oauth2.googleapis.com/revoke";
const FOLDER = "application/vnd.google-apps.folder";
const getUserId = (jwt: string) => Promise.resolve(jwt === "jwt-u1" ? "u1" : jwt === "jwt-u2" ? "u2" : null);

type Route = [string, (c: Call) => Response | Promise<Response>];

async function setup(routes: Route[], users = ["u1"]) {
  const store = await connectedStore(users);
  let refreshes = 0;
  const f = fakeFetch([
    [TOKEN_URL, (c) => {
      refreshes++;
      const r = new URLSearchParams(c.body).get("refresh_token")!;
      return jsonRes({ access_token: `ACC${refreshes}-${r}` });
    }],
    [REVOKE, () => jsonRes({})],
    ...routes,
  ]);
  const cache = new Map();
  const run = async (action: string | undefined, body: Record<string, unknown> = {}, jwt = "jwt-u1") => {
    const req = new Request("https://x/functions/v1/drive", {
      method: "POST",
      headers: { "Content-Type": "application/json", ...(jwt ? { Authorization: `Bearer ${jwt}` } : {}) },
      body: JSON.stringify(action === undefined ? body : { action, ...body }),
    });
    return await handle(req, { cfg: CFG, store, fetchFn: f.fn, getUserId, tokenCache: cache });
  };
  return { store, f, run, refreshes: () => refreshes, cache };
}

const files = (...items: Record<string, unknown>[]) => jsonRes({ files: items });
const api = (calls: Call[], prefix: string) => calls.filter((c) => c.url.startsWith(prefix));

// ---------------------------------------------------------------- autenticação / protocolo

Deno.test("sem JWT válido => 401 e nada é chamado; GET => 405; OPTIONS => 204; sem cfg => 500", async () => {
  const s = await setup([]);
  for (const jwt of ["", "jwt-ruim"]) {
    const r = await s.run("list", {}, jwt);
    assertEquals(r.status, 401);
    await r.body?.cancel();
  }
  assertEquals(s.f.calls.length, 0);

  const get = await handle(new Request("https://x/", { method: "GET" }), { cfg: CFG, store: s.store, fetchFn: s.f.fn, getUserId });
  assertEquals(get.status, 405);
  await get.body?.cancel();
  const opt = await handle(new Request("https://x/", { method: "OPTIONS" }), { cfg: CFG, store: s.store, fetchFn: s.f.fn, getUserId });
  assertEquals(opt.status, 204);
  const nocfg = await handle(new Request("https://x/", { method: "POST", headers: { Authorization: "Bearer jwt-u1" } }), { cfg: null, store: s.store, fetchFn: s.f.fn, getUserId });
  assertEquals(nocfg.status, 500);
  await nocfg.body?.cancel();
});

Deno.test("ação desconhecida ou ausente => 400", async () => {
  const s = await setup([]);
  for (const a of ["apagar_tudo", undefined]) {
    const r = await s.run(a, {});
    assertEquals(r.status, 400);
    await r.body?.cancel();
  }
});

Deno.test("sem conta do drive => 409 not_connected e nenhuma chamada ao Google", async () => {
  const s = await setup([], ["u1"]);
  const r = await s.run("list", {}, "jwt-u2");
  assertEquals(r.status, 409);
  assertEquals((await r.json()).code, "not_connected");
  assertEquals(s.f.calls.length, 0);
});

// ---------------------------------------------------------------- list / search

Deno.test("list usa a pasta raiz Organizacional, ordena pastas primeiro e mapeia os itens", async () => {
  const s = await setup([
    [`${DRIVE}/files/ROOT-U-u1?`, () => jsonRes({ id: "ROOT-U-u1", name: "Organizacional", parents: ["MEUDRIVE"] })],
    [`${DRIVE}/files?`, () =>
      files(
        { id: "f1", name: "Provas", mimeType: FOLDER, modifiedTime: "2026-10-01T10:00:00Z", shared: false },
        { id: "a1", name: "Edital.pdf", mimeType: "application/pdf", size: "2048", webViewLink: "https://drive.google.com/file/d/a1/view", iconLink: "https://i/x.png", shared: true },
      )],
  ]);
  const r = await s.run("list");
  assertEquals(r.status, 200);
  const body = await r.json();
  assertEquals(body.folder, { id: "ROOT-U-u1", name: "Organizacional", parents: ["MEUDRIVE"] });
  assertEquals(body.items.length, 2);
  assertEquals(body.items[0].isFolder, true);
  assertEquals(body.items[1], {
    id: "a1", name: "Edital.pdf", mimeType: "application/pdf", isFolder: false, size: 2048,
    modifiedTime: null, webViewLink: "https://drive.google.com/file/d/a1/view", iconLink: "https://i/x.png", shared: true,
  });
  const list = new URL(api(s.f.calls, `${DRIVE}/files?`)[0].url).searchParams;
  assertEquals(list.get("q"), "'ROOT-U-u1' in parents and trashed = false");
  assertEquals(list.get("orderBy"), "folder,name");
  assertEquals(list.get("pageSize"), "1000");
  assertEquals(body.truncated, false);
  // token de acesso veio do refresh token DESTE usuário
  assertEquals(api(s.f.calls, `${DRIVE}/files?`)[0].headers.get("authorization"), "Bearer ACC1-R-u1");
});

Deno.test("list 'root' abre o Meu Drive; ids estranhos são recusados sem consultar o Drive", async () => {
  const s = await setup([
    [`${DRIVE}/files/root?`, () => jsonRes({ id: "0AReal", name: "Meu Drive" })],
    [`${DRIVE}/files?`, () => files()],
  ]);
  const ok = await s.run("list", { folderId: "root" });
  assertEquals(ok.status, 200);
  assertEquals((await ok.json()).folder, { id: "0AReal", name: "Meu Drive", parents: [] });
  assertEquals(new URL(api(s.f.calls, `${DRIVE}/files?`)[0].url).searchParams.get("q"), "'root' in parents and trashed = false");

  const before = s.f.calls.length;
  for (const bad of ["x' or '1'='1", "a b", "../x", 5, ""]) {
    const r = await s.run("list", { folderId: bad });
    assertEquals(r.status, 400);
    await r.body?.cancel();
  }
  assertEquals(s.f.calls.length, before);
});

Deno.test("search escapa aspas e barras, exige texto e limita o tamanho", async () => {
  const s = await setup([[`${DRIVE}/files?`, () => files({ id: "a", name: "d'Água", mimeType: "text/plain" })]]);
  const r = await s.run("search", { q: "d'Ág\\ua" });
  assertEquals(r.status, 200);
  assertEquals((await r.json()).items[0].name, "d'Água");
  const q = new URL(api(s.f.calls, `${DRIVE}/files?`)[0].url).searchParams.get("q")!;
  assertEquals(q, "name contains 'd\\'Ág\\\\ua' and trashed = false");
  for (const bad of ["", "   ", "x".repeat(201), 3]) {
    const b = await s.run("search", { q: bad });
    assertEquals(b.status, 400);
    await b.body?.cancel();
  }
});

// ---------------------------------------------------------------- cache do token

Deno.test("o access token é reaproveitado entre chamadas do mesmo usuário e separado entre usuários", async () => {
  const s = await setup([
    [`${DRIVE}/files?`, () => files()],
    [`${DRIVE}/files/`, () => jsonRes({ id: "x", name: "n" })],
  ], ["u1", "u2"]);
  for (let i = 0; i < 3; i++) await (await s.run("search", { q: "a" })).body?.cancel();
  assertEquals(s.refreshes(), 1);
  await (await s.run("search", { q: "a" }, "jwt-u2")).body?.cancel();
  assertEquals(s.refreshes(), 2);
  const last = api(s.f.calls, `${DRIVE}/files?`).at(-1)!;
  assertEquals(last.headers.get("authorization"), "Bearer ACC2-R-u2");
});

Deno.test("401 do Drive renova o token uma vez e repete; segunda falha marca auth_required", async () => {
  let n = 0;
  const s = await setup([[`${DRIVE}/files?`, (c) => {
    n++;
    return c.headers.get("authorization") === "Bearer ACC1-R-u1" ? jsonRes({ error: { message: "x" } }, 401) : files();
  }]]);
  const ok = await s.run("search", { q: "a" });
  assertEquals(ok.status, 200);
  await ok.body?.cancel();
  assertEquals(s.refreshes(), 2);
  assertEquals(n, 2);

  const s2 = await setup([[`${DRIVE}/files?`, () => jsonRes({ error: {} }, 401)]]);
  const r = await s2.run("search", { q: "a" });
  assertEquals(r.status, 409);
  assertEquals((await r.json()).code, "auth_required");
  assertEquals(s2.store.states.get("u1")?.status, "auth_required");
  assertEquals(s2.store.accounts.has("u1"), true); // não apaga a conta: o usuário reconecta
});

Deno.test("invalid_grant no refresh => auth_required", async () => {
  const store = await connectedStore();
  const f = fakeFetch([[TOKEN_URL, () => jsonRes({ error: "invalid_grant" }, 400)]]);
  const req = new Request("https://x/", { method: "POST", headers: { Authorization: "Bearer jwt-u1" }, body: JSON.stringify({ action: "list" }) });
  const r = await handle(req, { cfg: CFG, store, fetchFn: f.fn, getUserId, tokenCache: new Map() });
  assertEquals(r.status, 409);
  assertEquals((await r.json()).code, "auth_required");
  assertEquals(store.states.get("u1")?.status, "auth_required");
});

Deno.test("403 de permissão num arquivo NÃO derruba a conexão; erro do Google não vaza detalhes", async () => {
  const s = await setup([[`${DRIVE}/files/f1`, () => jsonRes({ error: { errors: [{ reason: "insufficientFilePermissions" }], message: "SEGREDO-INTERNO" } }, 403)]]);
  const r = await s.run("rename", { id: "f1", name: "Novo" });
  assertEquals(r.status, 403);
  const text = await r.text();
  assert(!text.includes("SEGREDO-INTERNO"));
  assertStringIncludes(text, "permissão");
  assertEquals(s.store.states.get("u1")?.status, "ok");
});

Deno.test("500/limite de taxa do Google => 502 genérico em pt-BR; 404 => 404", async () => {
  const s = await setup([
    [`${DRIVE}/files/boom`, () => jsonRes({ error: "interno" }, 500)],
    [`${DRIVE}/files/rate`, () => jsonRes({ error: { errors: [{ reason: "userRateLimitExceeded" }] } }, 403)],
    [`${DRIVE}/files/gone`, () => jsonRes({ error: {} }, 404)],
  ]);
  for (const id of ["boom", "rate"]) {
    const r = await s.run("trash", { id });
    assertEquals(r.status, 502);
    assertStringIncludes((await r.json()).error, "Google Drive");
  }
  const nf = await s.run("trash", { id: "gone" });
  assertEquals(nf.status, 404);
  await nf.body?.cancel();
  assertEquals(s.store.states.get("u1")?.status, "ok");
});

// ---------------------------------------------------------------- escritas

Deno.test("create_folder cria a pasta no pai e valida nome/pai", async () => {
  const s = await setup([[`${DRIVE}/files?fields=`, (c) => jsonRes({ id: "nova", name: JSON.parse(c.body).name, mimeType: FOLDER })]]);
  const r = await s.run("create_folder", { parentId: "P1", name: "  Provas 2026 " });
  assertEquals(r.status, 200);
  const body = await r.json();
  assertEquals(body.item.id, "nova");
  assertEquals(body.item.isFolder, true);
  const sent = JSON.parse(s.f.calls.at(-1)!.body);
  assertEquals(sent, { name: "Provas 2026", mimeType: FOLDER, parents: ["P1"] });
  assertEquals(s.f.calls.at(-1)!.method, "POST");
  for (const bad of [{ parentId: "P1", name: "" }, { parentId: "P1", name: "x".repeat(256) }, { parentId: "a b", name: "ok" }, { name: "ok" }]) {
    const b = await s.run("create_folder", bad);
    assertEquals(b.status, 400);
    await b.body?.cancel();
  }
});

Deno.test("ensure_folder acha a pasta existente ou cria", async () => {
  let exists = true;
  const s = await setup([
    [`${DRIVE}/files?q=`, () => files(...(exists ? [{ id: "imp", name: "Importados", mimeType: FOLDER }] : []))],
    [`${DRIVE}/files?fields=`, () => jsonRes({ id: "imp-nova", name: "Importados", mimeType: FOLDER })],
  ]);
  const a = await s.run("ensure_folder", { parentId: "ROOT", name: "Importados" });
  assertEquals((await a.json()).item.id, "imp");
  assertEquals(s.f.calls.filter((c) => c.method === "POST" && c.url.startsWith(`${DRIVE}/files?fields=`)).length, 0);
  exists = false;
  const b = await s.run("ensure_folder", { parentId: "ROOT", name: "Importados" });
  assertEquals((await b.json()).item.id, "imp-nova");
});

Deno.test("rename, trash e restore usam PATCH com o campo certo", async () => {
  const s = await setup([[`${DRIVE}/files/f1`, (c) => jsonRes({ id: "f1", name: JSON.parse(c.body).name ?? "n", mimeType: "text/plain" })]]);
  await (await s.run("rename", { id: "f1", name: " Novo nome.txt " })).body?.cancel();
  assertEquals(JSON.parse(s.f.calls.at(-1)!.body), { name: "Novo nome.txt" });
  assertEquals(s.f.calls.at(-1)!.method, "PATCH");
  const t = await s.run("trash", { id: "f1" });
  assertEquals(await t.json(), { ok: true });
  assertEquals(JSON.parse(s.f.calls.at(-1)!.body), { trashed: true });
  await (await s.run("restore", { id: "f1" })).body?.cancel();
  assertEquals(JSON.parse(s.f.calls.at(-1)!.body), { trashed: false });
  for (const a of ["rename", "trash", "restore"]) {
    const b = await s.run(a, { id: "../x", name: "n" });
    assertEquals(b.status, 400);
    await b.body?.cancel();
  }
});

Deno.test("move troca os pais (addParents/removeParents)", async () => {
  const s = await setup([
    [`${DRIVE}/files/f1?fields=parents`, () => jsonRes({ parents: ["A", "B"] })],
    [`${DRIVE}/files/f1?`, () => jsonRes({ id: "f1", name: "x", mimeType: "text/plain" })],
  ]);
  const r = await s.run("move", { id: "f1", toFolderId: "DEST" });
  assertEquals(await r.json(), { ok: true });
  const patch = s.f.calls.find((c) => c.method === "PATCH")!;
  const q = new URL(patch.url).searchParams;
  assertEquals(q.get("addParents"), "DEST");
  assertEquals(q.get("removeParents"), "A,B");
  const bad = await s.run("move", { id: "f1", toFolderId: "x y" });
  assertEquals(bad.status, 400);
  await bad.body?.cancel();
});

// ---------------------------------------------------------------- compartilhamento

Deno.test("share convida por e-mail com o papel escolhido, sem notificar por padrão", async () => {
  const s = await setup([[`${DRIVE}/files/f1/permissions`, () => jsonRes({ id: "perm1" })]]);
  const r = await s.run("share", { id: "f1", email: "amiga@exemplo.com", role: "writer" });
  assertEquals(await r.json(), { ok: true });
  const c = s.f.calls.find((x) => x.method === "POST" && x.url.includes("/permissions"))!;
  assertEquals(JSON.parse(c.body), { type: "user", role: "writer", emailAddress: "amiga@exemplo.com" });
  assertEquals(new URL(c.url).searchParams.get("sendNotificationEmail"), "false");

  await (await s.run("share", { id: "f1", email: "amiga@exemplo.com", role: "reader", notify: true })).body?.cancel();
  assertEquals(new URL(s.f.calls.at(-1)!.url).searchParams.get("sendNotificationEmail"), "true");

  for (const bad of [{ email: "nao-e-email", role: "reader" }, { email: "a@b.com", role: "owner" }, { email: "a@b.com" }]) {
    const b = await s.run("share", { id: "f1", ...bad });
    assertEquals(b.status, 400);
    await b.body?.cancel();
  }
});

Deno.test("share_link liga (permissão anyone/reader) e devolve o link; desliga removendo só a permissão anyone", async () => {
  const s = await setup([
    [`${DRIVE}/files/f1/permissions`, (c) => {
      if (c.method === "DELETE") return new Response(null, { status: 204 });
      if (c.method === "POST") return jsonRes({ id: "pub" });
      return jsonRes({ permissions: [{ id: "pub", type: "anyone", role: "reader" }, { id: "p2", type: "user", role: "writer", emailAddress: "a@b.com" }] });
    }],
    [`${DRIVE}/files/f1?fields=webViewLink`, () => jsonRes({ webViewLink: "https://drive.google.com/file/d/f1/view" })],
  ]);
  const on = await s.run("share_link", { id: "f1", enabled: true });
  assertEquals(await on.json(), { webViewLink: "https://drive.google.com/file/d/f1/view" });
  const post = s.f.calls.find((c) => c.method === "POST" && c.url.includes("/permissions"))!;
  assertEquals(JSON.parse(post.body), { type: "anyone", role: "reader" });

  const off = await s.run("share_link", { id: "f1", enabled: false });
  assertEquals((await off.json()).webViewLink, "https://drive.google.com/file/d/f1/view");
  const dels = s.f.calls.filter((c) => c.method === "DELETE");
  assertEquals(dels.length, 1);
  assertEquals(dels[0].url, `${DRIVE}/files/f1/permissions/pub`);

  const bad = await s.run("share_link", { id: "f1", enabled: "sim" });
  assertEquals(bad.status, 400);
  await bad.body?.cancel();
});

Deno.test("permissions lista quem tem acesso; unshare remove uma permissão", async () => {
  const s = await setup([[`${DRIVE}/files/f1/permissions`, (c) =>
    c.method === "DELETE" ? new Response(null, { status: 204 }) : jsonRes({ permissions: [
      { id: "o", type: "user", role: "owner", emailAddress: "eu@g.com" },
      { id: "pub", type: "anyone", role: "reader" },
      { id: "p2", type: "user", role: "commenter", emailAddress: "a@b.com" },
    ] })]]);
  const r = await s.run("permissions", { id: "f1" });
  assertEquals((await r.json()).permissions, [
    { id: "o", email: "eu@g.com", role: "owner", type: "user" },
    { id: "pub", email: null, role: "reader", type: "anyone" },
    { id: "p2", email: "a@b.com", role: "commenter", type: "user" },
  ]);
  const u = await s.run("unshare", { id: "f1", permissionId: "p2" });
  assertEquals(await u.json(), { ok: true });
  assertEquals(s.f.calls.at(-1)!.method, "DELETE");
  const bad = await s.run("unshare", { id: "f1", permissionId: "p/2" });
  assertEquals(bad.status, 400);
  await bad.body?.cancel();
});

// ---------------------------------------------------------------- upload

Deno.test("upload_session cria a sessão resumable no servidor e devolve só a URL", async () => {
  const s = await setup([[`${UPLOAD}/files`, () =>
    new Response(null, { status: 200, headers: { Location: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=XYZ" } })]]);
  const r = await s.run("upload_session", { parentId: "P1", name: "Edital.pdf", mimeType: "application/pdf", size: 1234 });
  assertEquals(await r.json(), { uploadUrl: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=XYZ" });
  const c = s.f.calls.find((x) => x.url.startsWith(UPLOAD))!;
  assertEquals(c.method, "POST");
  assertEquals(c.headers.get("x-upload-content-type"), "application/pdf");
  assertEquals(c.headers.get("x-upload-content-length"), "1234");
  assertEquals(JSON.parse(c.body), { name: "Edital.pdf", parents: ["P1"], mimeType: "application/pdf" });
  assertEquals(new URL(c.url).searchParams.get("uploadType"), "resumable");
});

Deno.test("upload_session valida os campos e recusa Location fora do Google", async () => {
  const s = await setup([[`${UPLOAD}/files`, () => new Response(null, { status: 200, headers: { Location: "https://evil.example/up" } })]]);
  const evil = await s.run("upload_session", { parentId: "P1", name: "a.pdf", mimeType: "application/pdf", size: 10 });
  assertEquals(evil.status >= 400, true);
  assert(!(await evil.text()).includes("evil.example"));

  for (const bad of [
    { parentId: "P1", name: "", mimeType: "a/b", size: 1 },
    { parentId: "P1", name: "a", mimeType: "", size: 1 },
    { parentId: "P1", name: "a", mimeType: "a/b", size: -1 },
    { parentId: "P1", name: "a", mimeType: "a/b", size: 1.5 },
    { parentId: "P1", name: "a", mimeType: "a/b", size: "10" },
    { parentId: "x y", name: "a", mimeType: "a/b", size: 1 },
  ]) {
    const b = await s.run("upload_session", bad);
    assertEquals(b.status, 400);
    await b.body?.cancel();
  }
});

// ---------------------------------------------------------------- desconectar

Deno.test("disconnect revoga o refresh token, apaga a conta e zera o estado só deste usuário", async () => {
  const s = await setup([], ["u1", "u2"]);
  const r = await s.run("disconnect");
  assertEquals(await r.json(), { ok: true });
  assertEquals(new URLSearchParams(s.f.calls.find((c) => c.url === REVOKE)!.body).get("token"), "R-u1");
  assertEquals(s.store.accounts.has("u1"), false);
  assertEquals(s.store.states.get("u1"), {
    user_id: "u1", status: "not_connected", account_email: null, root_folder_id: null, message: null, connected_at: null,
  });
  assertEquals(s.store.accounts.has("u2"), true);
  assertEquals(s.store.states.get("u2")?.status, "ok");
  assertEquals([...s.cache.keys()].some((k) => k.startsWith("u1")), false);
});

Deno.test("disconnect funciona mesmo se a revogação falhar ou não houver conta", async () => {
  const store = await connectedStore();
  const f = fakeFetch([[REVOKE, () => Promise.reject(new TypeError("rede"))]]);
  const mk = (jwt: string) => new Request("https://x/", { method: "POST", headers: { Authorization: `Bearer ${jwt}` }, body: JSON.stringify({ action: "disconnect" }) });
  const r = await handle(mk("jwt-u1"), { cfg: CFG, store, fetchFn: f.fn, getUserId, tokenCache: new Map() });
  assertEquals(r.status, 200);
  await r.body?.cancel();
  assertEquals(store.accounts.size, 0);
  const again = await handle(mk("jwt-u1"), { cfg: CFG, store, fetchFn: f.fn, getUserId, tokenCache: new Map() });
  assertEquals(again.status, 200);
  await again.body?.cancel();
});

// ---------------------------------------------------------------- desconectar: Gmail e Drive dividem o mesmo client OAuth

Deno.test("disconnect NÃO revoga o token se o mesmo usuário tem Gmail com o mesmo e-mail; só apaga a linha e o estado", async () => {
  const s = await setup([], ["u1", "u2"]);
  s.store.siblings.set("u1", ["U1@g.com"]); // mesmo e-mail (sem diferenciar maiúsculas)
  const r = await s.run("disconnect");
  assertEquals(await r.json(), { ok: true });
  assertEquals(s.f.calls.filter((c) => c.url === REVOKE).length, 0);
  assertEquals(s.store.accounts.has("u1"), false);
  assertEquals(s.store.states.get("u1")?.status, "not_connected");
  assertEquals(s.store.accounts.has("u2"), true);
});

Deno.test("disconnect revoga se a outra conta do usuário é de outro e-mail", async () => {
  const s = await setup([]);
  s.store.siblings.set("u1", ["outra-pessoa@g.com"]);
  await (await s.run("disconnect")).body?.cancel();
  assertEquals(s.f.calls.filter((c) => c.url === REVOKE).length, 1);
});

// ---------------------------------------------------------------- cache do token amarrado ao refresh token

Deno.test("trocar o refresh token (reconectar) descarta o access token em cache e usa o novo", async () => {
  const s = await setup([[`${DRIVE}/files?`, () => files()]]);
  await (await s.run("search", { q: "a" })).body?.cancel();
  await (await s.run("search", { q: "a" })).body?.cancel();
  assertEquals(s.refreshes(), 1); // segunda chamada veio do cache
  const antes = api(s.f.calls, `${DRIVE}/files?`);
  assertEquals(antes[1].headers.get("authorization"), "Bearer ACC1-R-u1");

  // o usuário reconecta: a linha ganha outro refresh token cifrado
  const acct = s.store.accounts.get("u1")!;
  s.store.accounts.set("u1", { ...acct, refresh_token_enc: await encryptToken("R-novo", KEY) });
  await (await s.run("search", { q: "a" })).body?.cancel();
  assertEquals(s.refreshes(), 2);
  assertEquals(api(s.f.calls, `${DRIVE}/files?`).at(-1)!.headers.get("authorization"), "Bearer ACC2-R-novo");
});

// ---------------------------------------------------------------- paginação

/** Servidor falso paginado: respeita pageSize/pageToken (token = índice), com no máximo [maxPage] por página. */
function paged(total: number, key: "files" | "permissions", maxPage: number, mk: (i: number) => Record<string, unknown>) {
  return (c: Call) => {
    const q = new URL(c.url).searchParams;
    const start = Number(q.get("pageToken") ?? 0);
    const end = Math.min(start + Math.min(Number(q.get("pageSize")), maxPage), total);
    const rows = Array.from({ length: end - start }, (_, k) => mk(start + k));
    return jsonRes({ [key]: rows, ...(end < total ? { nextPageToken: String(end) } : {}) });
  };
}
const file = (i: number) => ({ id: `f${i}`, name: `Arquivo ${i}`, mimeType: "text/plain" });

Deno.test("list pagina com nextPageToken, corta em 1000 itens e avisa truncated", async () => {
  const s = await setup([
    [`${DRIVE}/files/ROOT-U-u1?`, () => jsonRes({ id: "ROOT-U-u1", name: "Organizacional" })],
    [`${DRIVE}/files?`, paged(1500, "files", 400, file)],
  ]);
  const body = await (await s.run("list")).json();
  assertEquals(body.items.length, 1000);
  assertEquals(body.truncated, true);
  assertEquals(body.items[999].id, "f999");
  const reqs = api(s.f.calls, `${DRIVE}/files?`).map((c) => new URL(c.url).searchParams);
  assertEquals(reqs.length, 3); // 400 + 400 + 200
  assertEquals(reqs[1].get("pageToken"), "400");
  assertEquals(reqs[2].get("pageSize"), "200");
  assertStringIncludes(reqs[0].get("fields")!, "nextPageToken");
});

Deno.test("list sem excesso junta as páginas e não marca truncated", async () => {
  const s = await setup([
    [`${DRIVE}/files/ROOT-U-u1?`, () => jsonRes({ id: "ROOT-U-u1", name: "Organizacional" })],
    [`${DRIVE}/files?`, paged(700, "files", 300, file)],
  ]);
  const body = await (await s.run("list")).json();
  assertEquals(body.items.length, 700);
  assertEquals(body.truncated, false);
});

Deno.test("list com exatamente 1000 itens não marca truncated", async () => {
  const s = await setup([
    [`${DRIVE}/files/ROOT-U-u1?`, () => jsonRes({ id: "ROOT-U-u1", name: "Organizacional" })],
    [`${DRIVE}/files?`, paged(1000, "files", 1000, file)],
  ]);
  const body = await (await s.run("list")).json();
  assertEquals(body.items.length, 1000);
  assertEquals(body.truncated, false);
});

Deno.test("search pagina até 200 itens e avisa truncated", async () => {
  const s = await setup([[`${DRIVE}/files?`, paged(500, "files", 100, file)]]);
  const body = await (await s.run("search", { q: "arq" })).json();
  assertEquals(body.items.length, 200);
  assertEquals(body.truncated, true);
  assertEquals(api(s.f.calls, `${DRIVE}/files?`).length, 2);

  const few = await setup([[`${DRIVE}/files?`, paged(30, "files", 100, file)]]);
  const b2 = await (await few.run("search", { q: "arq" })).json();
  assertEquals(b2.items.length, 30);
  assertEquals(b2.truncated, false);
});

Deno.test("permissions pagina até 200 itens e avisa truncated", async () => {
  const perm = (i: number) => ({ id: `p${i}`, type: "user", role: "reader", emailAddress: `u${i}@x.com` });
  const s = await setup([[`${DRIVE}/files/f1/permissions`, paged(350, "permissions", 100, perm)]]);
  const body = await (await s.run("permissions", { id: "f1" })).json();
  assertEquals(body.permissions.length, 200);
  assertEquals(body.truncated, true);
  assertStringIncludes(new URL(api(s.f.calls, `${DRIVE}/files/f1/permissions`)[0].url).searchParams.get("fields")!, "nextPageToken");
});

// ---------------------------------------------------------------- mover

Deno.test("move para a pasta onde o item já está (único pai) não chama o Drive para alterar e responde ok", async () => {
  const s = await setup([[`${DRIVE}/files/f1?fields=parents`, () => jsonRes({ parents: ["DEST"] })]]);
  const r = await s.run("move", { id: "f1", toFolderId: "DEST" });
  assertEquals(await r.json(), { ok: true });
  assertEquals(s.f.calls.filter((c) => c.method === "PATCH").length, 0);
});

Deno.test("move nunca remove o destino dos pais quando o item está em várias pastas", async () => {
  const s = await setup([
    [`${DRIVE}/files/f1?fields=parents`, () => jsonRes({ parents: ["A", "DEST"] })],
    [`${DRIVE}/files/f1?`, () => jsonRes({ id: "f1" })],
  ]);
  await (await s.run("move", { id: "f1", toFolderId: "DEST" })).body?.cancel();
  const q = new URL(s.f.calls.find((c) => c.method === "PATCH")!.url).searchParams;
  assertEquals(q.get("removeParents"), "A");
  assertEquals(q.has("addParents"), false);
});

// ---------------------------------------------------------------- upload: mime e URL

Deno.test("upload_session recusa mime com * ou de tipo nativo do Google (application/vnd.google-apps.*)", async () => {
  const s = await setup([[`${UPLOAD}/files`, () => new Response(null, { status: 200, headers: { Location: "https://www.googleapis.com/upload/drive/v3/files?upload_id=X" } })]]);
  for (const mimeType of ["*/*", "image/*", "application/vnd.google-apps.document", "Application/Vnd.Google-Apps.folder"]) {
    const b = await s.run("upload_session", { parentId: "P1", name: "a", mimeType, size: 1 });
    assertEquals(b.status, 400, mimeType);
    await b.body?.cancel();
  }
  assertEquals(api(s.f.calls, UPLOAD).length, 0);
  const ok = await s.run("upload_session", { parentId: "P1", name: "a", mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document", size: 1 });
  assertEquals(ok.status, 200);
  await ok.body?.cancel();
});

Deno.test("upload_session só aceita Location em www.googleapis.com", async () => {
  for (const loc of [
    "https://evilgoogleapis.com/up",
    "https://storage.googleapis.com/up",
    "https://www.googleapis.com.evil.example/up",
    "http://www.googleapis.com/up",
    "https://user:pw@www.googleapis.com/up",
  ]) {
    const s = await setup([[`${UPLOAD}/files`, () => new Response(null, { status: 200, headers: { Location: loc } })]]);
    const r = await s.run("upload_session", { parentId: "P1", name: "a.pdf", mimeType: "application/pdf", size: 10 });
    assertEquals(r.status >= 400, true, loc);
    await r.body?.cancel();
  }
});
