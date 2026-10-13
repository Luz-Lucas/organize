import { assert, assertEquals } from "jsr:@std/assert@1";
import { verifyState, verifyStateInfo } from "../_shared/gmail.ts";
import { CFG } from "../_shared/gmail_testutil.ts";
import { handle } from "./handler.ts";

const U = "11111111-1111-1111-1111-111111111111";
const getUserId = (jwt: string) => Promise.resolve(jwt === "jwt-bom" ? U : null);
const post = (headers: Record<string, string>, body?: unknown) =>
  new Request("https://x/functions/v1/gmail-connect", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });

Deno.test("connect devolve a URL do Google com state assinado do usuário e login_hint", async () => {
  const res = await handle(post({ Authorization: "Bearer jwt-bom" }, { email: "seu-contato@exemplo.com" }), { cfg: CFG, getUserId });
  assertEquals(res.status, 200);
  const { url } = await res.json();
  const u = new URL(url);
  assertEquals(u.origin + u.pathname, "https://accounts.google.com/o/oauth2/v2/auth");
  assertEquals(u.searchParams.get("login_hint"), "seu-contato@exemplo.com");
  assertEquals(u.searchParams.get("scope"), "https://www.googleapis.com/auth/gmail.metadata");
  assertEquals(u.searchParams.get("access_type"), "offline");
  assertEquals(u.searchParams.get("prompt"), "consent");
  assertEquals(await verifyState(u.searchParams.get("state")!, CFG.stateSecret), U);
  for (const s of [CFG.clientSecret, CFG.tokenKey, CFG.stateSecret]) assert(!url.includes(s));
});

Deno.test("connect sem corpo funciona; e-mail inválido é 400; sem JWT válido é 401", async () => {
  const ok = await handle(post({ Authorization: "Bearer jwt-bom" }), { cfg: CFG, getUserId });
  assertEquals(ok.status, 200);
  assertEquals(new URL((await ok.json()).url).searchParams.has("login_hint"), false);

  const bad = await handle(post({ Authorization: "Bearer jwt-bom" }, { email: "isso não é e-mail&scope=x" }), { cfg: CFG, getUserId });
  assertEquals(bad.status, 400);
  await bad.body?.cancel();

  for (const h of [{}, { Authorization: "Bearer jwt-ruim" }] as Record<string, string>[]) {
    const r = await handle(post(h), { cfg: CFG, getUserId });
    assertEquals(r.status, 401);
    await r.body?.cancel();
  }
});

Deno.test("connect: GET => 405, OPTIONS => 204, sem configuração => 500", async () => {
  const get = await handle(new Request("https://x/", { method: "GET" }), { cfg: CFG, getUserId });
  assertEquals(get.status, 405);
  await get.body?.cancel();
  const opt = await handle(new Request("https://x/", { method: "OPTIONS" }), { cfg: CFG, getUserId });
  assertEquals(opt.status, 204);
  const nocfg = await handle(post({ Authorization: "Bearer jwt-bom" }), { cfg: null, getUserId });
  assertEquals(nocfg.status, 500);
  await nocfg.body?.cancel();
});

Deno.test("connect com provider drive devolve o consentimento do escopo drive e state do drive", async () => {
  const res = await handle(post({ Authorization: "Bearer jwt-bom" }, { provider: "drive", email: "contato@gmail.com" }), { cfg: CFG, getUserId });
  assertEquals(res.status, 200);
  const { url } = await res.json();
  const u = new URL(url);
  assertEquals(u.searchParams.get("scope"), "https://www.googleapis.com/auth/drive");
  assertEquals(u.searchParams.get("login_hint"), "contato@gmail.com");
  assertEquals(u.searchParams.get("redirect_uri"), CFG.redirectUri); // o mesmo URI já cadastrado
  assertEquals(await verifyStateInfo(u.searchParams.get("state")!, CFG.stateSecret), { userId: U, provider: "drive" });
});

Deno.test("connect com provider gmail explícito ou ausente continua sendo gmail", async () => {
  for (const body of [{ provider: "gmail" }, { provider: null }, {}] as unknown[]) {
    const res = await handle(post({ Authorization: "Bearer jwt-bom" }, body), { cfg: CFG, getUserId });
    const u = new URL((await res.json()).url);
    assertEquals(u.searchParams.get("scope"), "https://www.googleapis.com/auth/gmail.metadata");
    assertEquals((await verifyStateInfo(u.searchParams.get("state")!, CFG.stateSecret))?.provider, "gmail");
  }
});

Deno.test("connect recusa provider desconhecido (400)", async () => {
  for (const provider of ["outlook", 5, "DRIVE"]) {
    const res = await handle(post({ Authorization: "Bearer jwt-bom" }, { provider }), { cfg: CFG, getUserId });
    assertEquals(res.status, 400);
    await res.body?.cancel();
  }
});
