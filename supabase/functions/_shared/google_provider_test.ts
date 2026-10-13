import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  b64urlDecode,
  b64urlEncode,
  buildConsentUrl,
  DRIVE_SCOPE,
  GMAIL_LEGACY_SCOPE,
  GMAIL_SCOPE,
  hasModifyScope,
  scopeGranted,
  signState,
  siblingMatches,
  verifyState,
  verifyStateFull,
  verifyStateInfo,
} from "./gmail.ts";
import { CFG } from "./gmail_testutil.ts";

const U = "11111111-1111-1111-1111-111111111111";

Deno.test("state do drive carrega o provider e continua verificável como userId", async () => {
  const s = await signState(U, "segredo", 1000, undefined, "drive");
  assertEquals(await verifyStateInfo(s, "segredo", 2000), { userId: U, provider: "drive" });
  assertEquals(await verifyState(s, "segredo", 2000), U);
});

Deno.test("state sem provider (formato antigo do Gmail) vale como gmail", async () => {
  const s = await signState(U, "segredo", 1000);
  assertEquals(await verifyStateInfo(s, "segredo", 2000), { userId: U, provider: "gmail" });
});

Deno.test("state com provider desconhecido ou adulterado é recusado", async () => {
  const s = await signState(U, "segredo", 1000, undefined, "drive");
  const [payload, sig] = s.split(".");
  // troca o provider no payload mantendo a assinatura antiga
  const text = new TextDecoder().decode(b64urlDecode(payload));
  const forged = b64urlEncode(new TextEncoder().encode(text.replace(/drive$/, "gmail")));
  assertEquals(await verifyStateInfo(`${forged}.${sig}`, "segredo", 2000), null);
  assertEquals(await verifyStateInfo(`${payload}.${sig.slice(0, -2)}AA`, "segredo", 2000), null);
  assertEquals(await verifyStateInfo(s, "outro", 2000), null);
});

Deno.test("consentimento do drive pede só o escopo drive; o padrão é gmail.modify", () => {
  const d = new URL(buildConsentUrl(CFG, "st.sig", "contato@gmail.com", "drive")).searchParams;
  assertEquals(d.get("scope"), DRIVE_SCOPE);
  assertEquals(DRIVE_SCOPE, "https://www.googleapis.com/auth/drive");
  assertEquals(d.get("access_type"), "offline");
  assertEquals(d.get("prompt"), "consent");
  assertEquals(d.get("include_granted_scopes"), "false");
  assertEquals(d.get("login_hint"), "contato@gmail.com");
  const g = new URL(buildConsentUrl(CFG, "st.sig")).searchParams;
  assertEquals(g.get("scope"), GMAIL_SCOPE);
  assertEquals(GMAIL_SCOPE, "https://www.googleapis.com/auth/gmail.modify");
  assert(!buildConsentUrl(CFG, "s", undefined, "drive").includes(CFG.clientSecret));
});

Deno.test("siblingMatches compara o e-mail da outra linha sem diferenciar maiúsculas nem espaços", () => {
  assertEquals(siblingMatches([{ account_email: " Lucas@Gmail.com " }], "lucas@gmail.com"), true);
  assertEquals(siblingMatches([{ account_email: "outra@gmail.com" }], "lucas@gmail.com"), false);
  assertEquals(siblingMatches([], "lucas@gmail.com"), false);
  assertEquals(siblingMatches(null, "lucas@gmail.com"), false);
});

Deno.test("verifyStateFull expõe o nonce do state (único por state assinado)", async () => {
  const a = await signState(U, "segredo", 1000);
  const b = await signState(U, "segredo", 1000);
  const ia = await verifyStateFull(a, "segredo", 2000);
  const ib = await verifyStateFull(b, "segredo", 2000);
  assertEquals(ia?.userId, U);
  assertEquals(ia?.provider, "gmail");
  assert(typeof ia?.nonce === "string" && ia.nonce.length >= 16);
  assert(ia!.nonce !== ib!.nonce);
  assertEquals(await verifyStateFull(a, "outro", 2000), null);
});

Deno.test("scopeGranted: gmail aceita modify e o antigo metadata; drive só o drive; escopo parecido não conta", () => {
  assertEquals(GMAIL_LEGACY_SCOPE, "https://www.googleapis.com/auth/gmail.metadata");
  assertEquals(scopeGranted("gmail", `openid ${GMAIL_SCOPE}`), true);
  assertEquals(scopeGranted("gmail", GMAIL_LEGACY_SCOPE), true);
  assertEquals(scopeGranted("gmail", `${GMAIL_SCOPE}.x`), false);
  assertEquals(scopeGranted("gmail", "openid email"), false);
  assertEquals(scopeGranted("gmail", ""), false);
  assertEquals(scopeGranted("gmail", DRIVE_SCOPE), false);
  assertEquals(scopeGranted("drive", DRIVE_SCOPE), true);
  assertEquals(scopeGranted("drive", GMAIL_SCOPE), false);
  assertEquals(scopeGranted("drive", GMAIL_LEGACY_SCOPE), false);
});

Deno.test("hasModifyScope só é verdadeiro com gmail.modify exato na lista", () => {
  assertEquals(hasModifyScope(GMAIL_SCOPE), true);
  assertEquals(hasModifyScope(`${GMAIL_LEGACY_SCOPE} ${GMAIL_SCOPE}`), true);
  assertEquals(hasModifyScope(GMAIL_LEGACY_SCOPE), false);
  assertEquals(hasModifyScope(`${GMAIL_SCOPE}.x`), false);
  assertEquals(hasModifyScope(""), false);
  assertEquals(hasModifyScope(null), false);
  assertEquals(hasModifyScope(undefined), false);
});
