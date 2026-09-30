import { assertEquals } from "jsr:@std/assert@1";
import { collect } from "./collect.ts";
import type { FeedItem } from "./feed.ts";

const item = (url: string, title = url): FeedItem => ({
  url, title, summary: "", imageUrl: null, publishedAt: new Date("2026-09-28T12:00:00Z"),
});

const sources = [
  { id: "g1", name: "G1 / Principais", feed_url: "https://g1/principal" },
  { id: "g1pol", name: "G1 / Política", feed_url: "https://g1/politica" },
  { id: "folha", name: "Folha / Poder", feed_url: "https://folha/poder" },
];

Deno.test("um feed com erro não impede os outros e vai para failures", async () => {
  const subs = [{ user_id: "u1", source_id: "g1" }, { user_id: "u1", source_id: "folha" }];
  const { rows, failures } = await collect(subs, sources, (url) =>
    url.includes("folha") ? Promise.reject(new Error("HTTP 503")) : Promise.resolve([item("https://g1/a")]));
  assertEquals(rows.map((r) => r.url), ["https://g1/a"]);
  assertEquals(failures, [{ source: "Folha / Poder", error: "HTTP 503" }]);
});

Deno.test("a mesma notícia em dois feeds do mesmo usuário vira uma linha só", async () => {
  const subs = [{ user_id: "u1", source_id: "g1" }, { user_id: "u1", source_id: "g1pol" }];
  const { rows } = await collect(subs, sources, () => Promise.resolve([item("https://g1/mesma")]));
  assertEquals(rows.length, 1);
  assertEquals(rows[0].source_id, "g1");
});

Deno.test("cada feed é baixado uma vez mesmo com vários assinantes", async () => {
  const subs = [{ user_id: "u1", source_id: "g1" }, { user_id: "u2", source_id: "g1" }];
  let calls = 0;
  const { rows } = await collect(subs, sources, () => {
    calls++;
    return Promise.resolve([item("https://g1/a")]);
  });
  assertEquals(calls, 1);
  assertEquals(rows.map((r) => r.user_id).sort(), ["u1", "u2"]);
  assertEquals(rows[0].published_at, "2026-09-28T12:00:00.000Z");
});
