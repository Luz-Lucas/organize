import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { decodeFeedBytes, FeedError, normalizeUrl, parseFeed, stripHtml } from "./feed.ts";

const NOW = new Date("2026-09-28T15:00:00Z");

Deno.test("parse RSS 2.0 com CDATA, imagem e data com fuso", () => {
  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/"><channel><title>G1</title>
<item>
  <title><![CDATA[Nova IA do Google chega ao Brasil]]></title>
  <link>https://g1.globo.com/tec/ia.ghtml?utm_source=rss&amp;id=7#topo</link>
  <description><![CDATA[<img src="https://s.glbimg.com/foto.jpg" /><br />A empresa &amp; parceiros anunciaram&nbsp;hoje.]]></description>
  <pubDate>Mon, 28 Sep 2026 10:00:00 -0300</pubDate>
</item></channel></rss>`;
  const [item] = parseFeed(xml, NOW);
  assertEquals(item.title, "Nova IA do Google chega ao Brasil");
  assertEquals(item.url, "https://g1.globo.com/tec/ia.ghtml?id=7");
  assertEquals(item.imageUrl, "https://s.glbimg.com/foto.jpg");
  assertEquals(item.summary, "A empresa & parceiros anunciaram hoje.");
  assertEquals(item.publishedAt.toISOString(), "2026-09-28T13:00:00.000Z");
});

Deno.test("parse Atom com link alternate", () => {
  const xml = `<feed xmlns="http://www.w3.org/2005/Atom"><title>X</title>
<entry><title>Economia cresce</title>
<link rel="self" href="https://x.dev/self"/><link rel="alternate" href="https://x.dev/economia"/>
<summary>Resumo</summary><published>2026-09-28T12:00:00Z</published></entry></feed>`;
  const [item] = parseFeed(xml, NOW);
  assertEquals(item.url, "https://x.dev/economia");
  assertEquals(item.summary, "Resumo");
  assertEquals(item.publishedAt.toISOString(), "2026-09-28T12:00:00.000Z");
});

Deno.test("decodifica ISO-8859-1 pela declaração XML", () => {
  const xml = `<?xml version="1.0" encoding="ISO-8859-1"?><rss><channel><item><title>Eleição em São Paulo</title><link>https://f.dev/a</link></item></channel></rss>`;
  const bytes = Uint8Array.from(xml, (c) => c.charCodeAt(0));
  const [item] = parseFeed(decodeFeedBytes(bytes, "text/xml"), NOW);
  assertEquals(item.title, "Eleição em São Paulo");
});

Deno.test("decodifica pelo charset do Content-Type quando não há declaração", () => {
  const xml = `<rss><channel><item><title>Educação</title><link>https://f.dev/b</link></item></channel></rss>`;
  const bytes = Uint8Array.from(xml, (c) => c.charCodeAt(0));
  assertEquals(parseFeed(decodeFeedBytes(bytes, "text/xml; charset=ISO-8859-1"), NOW)[0].title, "Educação");
});

Deno.test("página HTML não é feed", () => {
  assertThrows(() => parseFeed("<!doctype html><html><body>g1</body></html>", NOW), FeedError);
});

Deno.test("item único (não lista), sem link é ignorado, sem data usa agora, data futura vira agora", () => {
  const single = `<rss><channel><item><title>Único</title><link>https://a.dev/1</link></item></channel></rss>`;
  const [item] = parseFeed(single, NOW);
  assertEquals(item.publishedAt, NOW);
  const mixed = `<rss><channel>
<item><title>Sem link</title></item>
<item><title>Futuro</title><link>https://a.dev/2</link><pubDate>Wed, 30 Sep 2026 10:00:00 GMT</pubDate></item>
</channel></rss>`;
  const items = parseFeed(mixed, NOW);
  assertEquals(items.map((i) => i.title), ["Futuro"]);
  assertEquals(items[0].publishedAt, NOW);
});

Deno.test("stripHtml decodifica entidades sem decodificar duas vezes e trunca", () => {
  assertEquals(stripHtml("<p>A &amp;lt;b&amp;gt; &#233; x</p>"), "A &lt;b&gt; é x");
  assertEquals(stripHtml("a".repeat(300), 10), "aaaaaaaaa…");
});

Deno.test("normalizeUrl remove utm_* e fragmento e recusa esquemas estranhos", () => {
  assertEquals(normalizeUrl(" https://a.dev/x?utm_medium=rss&p=1#c "), "https://a.dev/x?p=1");
  assertEquals(normalizeUrl("javascript:alert(1)"), null);
  assertEquals(normalizeUrl("não é url"), null);
});
