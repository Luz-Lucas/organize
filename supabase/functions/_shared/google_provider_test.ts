import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  b64urlDecode,
  b64urlEncode,
  buildConsentUrl,
  DRIVE_SCOPE,
  GMAIL_SCOPE,
  signState,
  verifyState,
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

Deno.test("consentimento do drive pede só o escopo drive; o padrão continua gmail.metadata", () => {
  const d = new URL(buildConsentUrl(CFG, "st.sig", "contato@gmail.com", "drive")).searchParams;
  assertEquals(d.get("scope"), DRIVE_SCOPE);
  assertEquals(DRIVE_SCOPE, "https://www.googleapis.com/auth/drive");
  assertEquals(d.get("access_type"), "offline");
  assertEquals(d.get("prompt"), "consent");
  assertEquals(d.get("include_granted_scopes"), "false");
  assertEquals(d.get("login_hint"), "contato@gmail.com");
  const g = new URL(buildConsentUrl(CFG, "st.sig")).searchParams;
  assertEquals(g.get("scope"), GMAIL_SCOPE);
  assert(!buildConsentUrl(CFG, "s", undefined, "drive").includes(CFG.clientSecret));
});
