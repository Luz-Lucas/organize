import { assertEquals } from "jsr:@std/assert@1";
import { isAuthorized } from "./auth.ts";

const req = (headers: Record<string, string>) => new Request("http://x", { method: "POST", headers });
const validUser = (jwt: string) => Promise.resolve(jwt === "jwt-bom");

Deno.test("aceita o segredo do cron", async () => {
  assertEquals(await isAuthorized(req({ "x-cron-secret": "s3" }), "s3", validUser), true);
});

Deno.test("aceita JWT de usuário válido", async () => {
  assertEquals(await isAuthorized(req({ Authorization: "Bearer jwt-bom" }), "s3", validUser), true);
});

Deno.test("recusa segredo errado, JWT inválido e ausência de credenciais", async () => {
  assertEquals(await isAuthorized(req({ "x-cron-secret": "errado" }), "s3", validUser), false);
  assertEquals(await isAuthorized(req({ Authorization: "Bearer jwt-ruim" }), "s3", validUser), false);
  assertEquals(await isAuthorized(req({}), undefined, validUser), false);
});

Deno.test("falha ao consultar o usuário conta como não autorizado", async () => {
  assertEquals(
    await isAuthorized(req({ Authorization: "Bearer x" }), "s3", () => Promise.reject(new Error("rede"))),
    false,
  );
});
