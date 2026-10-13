import { assert, assertEquals, assertNotEquals, assertRejects } from "jsr:@std/assert@1";
import {
  b64urlDecode,
  b64urlEncode,
  buildConsentUrl,
  decodeEncodedWords,
  decryptToken,
  encryptToken,
  loadConfig,
  parseFrom,
  parseMessage,
  parseSubject,
  safeEqual,
  signState,
  verifyState,
} from "./gmail.ts";
import { CFG, KEY } from "./gmail_testutil.ts";

const U = "11111111-1111-1111-1111-111111111111";

// ---------------------------------------------------------------- state

Deno.test("state: assina e verifica, devolvendo o userId", async () => {
  const s = await signState(U, "segredo", 1000);
  assertEquals(await verifyState(s, "segredo", 1000 + 5 * 60_000), U);
});

Deno.test("state: formato base64url(userId.exp.nonce).hmac e nonce diferente a cada vez", async () => {
  const s = await signState(U, "segredo", 1000);
  const [payload, sig] = s.split(".");
  assert(sig.length > 20);
  const [u, exp, nonce] = new TextDecoder().decode(b64urlDecode(payload)).split(".");
  assertEquals(u, U);
  assertEquals(exp, String(1000 + 10 * 60_000));
  assert(nonce.length >= 16);
  assertNotEquals(s, await signState(U, "segredo", 1000));
});

Deno.test("state: expirado (10 min) é recusado", async () => {
  const s = await signState(U, "segredo", 1000);
  assertEquals(await verifyState(s, "segredo", 1000 + 10 * 60_000 + 1), null);
});

Deno.test("state: adulterado, segredo errado e lixo são recusados", async () => {
  const s = await signState(U, "segredo", 1000);
  const [payload, sig] = s.split(".");
  const other = b64urlEncode(new TextEncoder().encode(`22222222-2222-2222-2222-222222222222.9999999999999.abc`));
  assertEquals(await verifyState(`${other}.${sig}`, "segredo", 1000), null);
  assertEquals(await verifyState(`${payload}.${sig.slice(0, -2)}AA`, "segredo", 1000), null);
  assertEquals(await verifyState(s, "outro-segredo", 1000), null);
  for (const lixo of ["", "abc", "a.b.c", "....", "!!.!!", `${payload}.`]) {
    assertEquals(await verifyState(lixo, "segredo", 1000), null);
  }
});

Deno.test("safeEqual compara em valor", async () => {
  assertEquals(await safeEqual("abc", "abc"), true);
  assertEquals(await safeEqual("abc", "abd"), false);
  assertEquals(await safeEqual("abc", "abcd"), false);
});

// ---------------------------------------------------------------- AES-GCM

Deno.test("AES-GCM: ida e volta, IV aleatório de 12 bytes na frente", async () => {
  const a = await encryptToken("1//refresh-token", KEY);
  const b = await encryptToken("1//refresh-token", KEY);
  assertNotEquals(a, b);
  assertEquals(await decryptToken(a, KEY), "1//refresh-token");
  const raw = atob(a);
  assertEquals(raw.length, 12 + "1//refresh-token".length + 16);
  assert(!a.includes("refresh-token"));
});

Deno.test("AES-GCM: adulteração, chave errada e lixo são detectados", async () => {
  const a = await encryptToken("segredo", KEY);
  const bytes = Uint8Array.from(atob(a), (c) => c.charCodeAt(0));
  bytes[bytes.length - 1] ^= 1;
  const tampered = btoa(String.fromCharCode(...bytes));
  await assertRejects(() => decryptToken(tampered, KEY));
  const otherKey = btoa(String.fromCharCode(...new Uint8Array(32).fill(9)));
  await assertRejects(() => decryptToken(a, otherKey));
  await assertRejects(() => decryptToken("curto", KEY));
  await assertRejects(() => decryptToken("@@@@", KEY));
});

Deno.test("AES-GCM: chave que não tem 32 bytes é recusada", async () => {
  await assertRejects(() => encryptToken("x", btoa("curta")));
});

// ---------------------------------------------------------------- cabeçalhos

Deno.test("From: formas de nome de exibição", () => {
  assertEquals(parseFrom("Maria Silva <maria@exemplo.com>"), { name: "Maria Silva", addr: "maria@exemplo.com" });
  assertEquals(parseFrom("<so@exemplo.com>"), { name: null, addr: "so@exemplo.com" });
  assertEquals(parseFrom("Fulano@Exemplo.COM"), { name: null, addr: "fulano@exemplo.com" });
  assertEquals(parseFrom("sem.nome@x.org (Fulano de Tal)"), { name: "Fulano de Tal", addr: "sem.nome@x.org" });
  assertEquals(parseFrom(""), { name: null, addr: null });
  assertEquals(parseFrom(null), { name: null, addr: null });
});

Deno.test("From: aspas, vírgula e <> dentro do nome, escape", () => {
  assertEquals(parseFrom('"Silva, Maria" <maria@x.com>'), { name: "Silva, Maria", addr: "maria@x.com" });
  assertEquals(parseFrom('"Loja <Oficial>" <loja@x.com>'), { name: "Loja <Oficial>", addr: "loja@x.com" });
  assertEquals(parseFrom('"João \\"Zé\\" Souza" <j@x.com>'), { name: 'João "Zé" Souza', addr: "j@x.com" });
  assertEquals(parseFrom("   Espaços   Demais   <e@x.com>"), { name: "Espaços Demais", addr: "e@x.com" });
});

Deno.test("From: lista de remetentes fica com o primeiro; nome igual ao e-mail some", () => {
  assertEquals(parseFrom('"A, B" <a@x.com>, C <c@x.com>'), { name: "A, B", addr: "a@x.com" });
  assertEquals(parseFrom('"a@x.com" <a@x.com>'), { name: null, addr: "a@x.com" });
});

Deno.test("From: encoded-words (B e Q) em nome com ou sem aspas", () => {
  assertEquals(parseFrom("=?UTF-8?B?Sm/Do28gU2lsdmE=?= <joao@x.com>"), { name: "João Silva", addr: "joao@x.com" });
  assertEquals(parseFrom('"=?UTF-8?Q?Jos=C3=A9_Pe=C3=B1a?=" <jose@x.com>'), { name: "José Peña", addr: "jose@x.com" });
});

Deno.test("Subject: RFC 2047 (UTF-8 B/Q, ISO-8859-1, palavras adjacentes)", () => {
  assertEquals(parseSubject("=?UTF-8?B?T2zDoSwgbXVuZG8h?="), "Olá, mundo!");
  assertEquals(parseSubject("=?UTF-8?Q?Reuni=C3=A3o_amanh=C3=A3?="), "Reunião amanhã");
  assertEquals(parseSubject("=?ISO-8859-1?Q?Aten=E7=E3o?="), "Atenção");
  assertEquals(parseSubject("=?UTF-8?B?T2zDoSw=?=\r\n =?UTF-8?B?IG11bmRvIQ==?="), "Olá, mundo!");
  assertEquals(parseSubject("Re: texto =?UTF-8?Q?com_acento_=C3=A9?= no meio"), "Re: texto com acento é no meio");
  assertEquals(decodeEncodedWords("=?UTF-8?X?lixo?="), "=?UTF-8?X?lixo?=");
});

Deno.test("Subject: ausente ou vazio vira null; quebras e controles são limpos", () => {
  assertEquals(parseSubject(undefined), null);
  assertEquals(parseSubject("   "), null);
  assertEquals(parseSubject("Linha 1\r\n\t Linha 2\u0007"), "Linha 1 Linha 2");
  assertEquals(parseSubject("x".repeat(900))!.length, 500);
});

Deno.test("mensagem: usa internalDate, UNREAD e cabeçalhos; sem Subject vem null", () => {
  const m = parseMessage("abc", {
    threadId: "t1",
    labelIds: ["INBOX", "UNREAD"],
    internalDate: "1760000000000",
    payload: { headers: [{ name: "from", value: "Ana <ana@x.com>" }] },
  });
  assertEquals(m, {
    gmail_id: "abc",
    thread_id: "t1",
    from_name: "Ana",
    from_addr: "ana@x.com",
    subject: null,
    received_at: new Date(1760000000000).toISOString(),
    unread: true,
  });
});

Deno.test("mensagem: sem internalDate cai no cabeçalho Date; data inválida vira null", () => {
  const headers = (d: string) => ({ payload: { headers: [{ name: "Date", value: d }] } });
  assertEquals(parseMessage("a", headers("Tue, 14 Oct 2025 10:00:00 +0000")).received_at, "2025-10-14T10:00:00.000Z");
  assertEquals(parseMessage("a", headers("não é data")).received_at, null);
  assertEquals(parseMessage("a", {}).unread, false);
});

// ---------------------------------------------------------------- URL de consentimento / config

Deno.test("URL de consentimento tem os parâmetros certos e nenhum segredo", () => {
  const url = new URL(buildConsentUrl(CFG, "st4te.sig", "contato@gmail.com"));
  assertEquals(url.origin + url.pathname, "https://accounts.google.com/o/oauth2/v2/auth");
  const p = url.searchParams;
  assertEquals(p.get("client_id"), CFG.clientId);
  assertEquals(p.get("redirect_uri"), CFG.redirectUri);
  assertEquals(p.get("response_type"), "code");
  assertEquals(p.get("access_type"), "offline");
  assertEquals(p.get("prompt"), "consent");
  assertEquals(p.get("scope"), "https://www.googleapis.com/auth/gmail.modify");
  assertEquals(p.get("include_granted_scopes"), "false");
  assertEquals(p.get("login_hint"), "contato@gmail.com");
  assertEquals(p.get("state"), "st4te.sig");
  const text = url.toString();
  for (const s of [CFG.clientSecret, CFG.tokenKey, CFG.stateSecret]) assert(!text.includes(s));
  assertEquals(new URL(buildConsentUrl(CFG, "s")).searchParams.has("login_hint"), false);
});

Deno.test("loadConfig monta o redirect URI e exige todos os segredos", () => {
  const env: Record<string, string> = {
    GOOGLE_CLIENT_ID: "id",
    GOOGLE_CLIENT_SECRET: "sec",
    GMAIL_TOKEN_KEY: KEY,
    STATE_SECRET: "st",
    SUPABASE_URL: "https://abc.supabase.co/",
  };
  assertEquals(loadConfig((k) => env[k])!.redirectUri, "https://abc.supabase.co/functions/v1/gmail-callback");
  assertEquals(loadConfig((k) => (k === "STATE_SECRET" ? undefined : env[k])), null);
});
