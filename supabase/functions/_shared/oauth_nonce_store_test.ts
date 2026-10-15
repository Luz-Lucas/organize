import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { createNonceStore } from "./oauth_nonce_store.ts";

type Rpc = (fn: string, args: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }>;
const dbWith = (rpc: Rpc) => ({ rpc }) as never;

Deno.test("nonce store chama consume_oauth_nonce e devolve true/false conforme o banco", async () => {
  const seen: [string, Record<string, unknown>][] = [];
  const store = createNonceStore(dbWith((fn, args) => {
    seen.push([fn, args]);
    return Promise.resolve({ data: seen.length === 1, error: null });
  }));
  assertEquals(await store.consume("abc"), true);
  assertEquals(await store.consume("abc"), false);
  assertEquals(seen[0], ["consume_oauth_nonce", { p_nonce: "abc" }]);
});

Deno.test("nonce store lança (sem detalhes do erro) se o banco falhar", async () => {
  const store = createNonceStore(dbWith(() => Promise.resolve({ data: null, error: { message: "segredo-interno" } })));
  const e = await assertRejects(() => store.consume("abc"));
  assertEquals((e as Error).message, "db:consumeNonce");
});
