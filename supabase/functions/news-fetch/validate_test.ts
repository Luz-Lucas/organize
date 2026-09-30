import { assertEquals } from "jsr:@std/assert@1";
import { FeedError } from "./feed.ts";
import { validateErrorMessage } from "./validate.ts";

Deno.test("FeedError usa a própria mensagem", () => {
  assertEquals(validateErrorMessage(new FeedError("não é um feed RSS/Atom")), "não é um feed RSS/Atom");
});

Deno.test("outros erros viram mensagem genérica sem texto cru", () => {
  assertEquals(validateErrorMessage(new TypeError("error sending request")), "não foi possível baixar o feed");
  assertEquals(validateErrorMessage(new Error("HTTP 404")), "não foi possível baixar o feed");
});
