import { XMLParser } from "npm:fast-xml-parser@4.5.0";

export interface FeedItem {
  url: string;
  title: string;
  summary: string;
  imageUrl: string | null;
  publishedAt: Date;
}

export class FeedError extends Error {}

export const USER_AGENT = "Organizacional/1.0 (+leitor pessoal de RSS)";

const parser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: "@_",
  textNodeName: "#text",
  processEntities: true,
  htmlEntities: true,
  trimValues: true,
});

// deno-lint-ignore no-explicit-any
type Node = any;

const asArray = <T>(v: T | T[] | undefined | null): T[] =>
  v === undefined || v === null ? [] : Array.isArray(v) ? v : [v];

function text(v: Node): string {
  if (typeof v === "string") return v;
  if (typeof v === "number") return String(v);
  if (v && typeof v === "object" && "#text" in v) return String(v["#text"]);
  return "";
}

export function decodeFeedBytes(bytes: Uint8Array, contentType: string | null): string {
  const head = new TextDecoder("latin1").decode(bytes.subarray(0, 200));
  const fromDecl = head.match(/<\?xml[^>]*encoding=["']([\w-]+)["']/i)?.[1];
  const fromHeader = contentType?.match(/charset=([\w-]+)/i)?.[1];
  const label = (fromDecl ?? fromHeader ?? "utf-8").toLowerCase();
  try {
    return new TextDecoder(label).decode(bytes);
  } catch {
    return new TextDecoder("utf-8").decode(bytes);
  }
}

export function stripHtml(html: string, max = 280): string {
  const plain = html
    .replace(/<[^>]*>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)))
    .replace(/&amp;/g, "&")
    .replace(/\s+/g, " ")
    .trim();
  return plain.length <= max ? plain : plain.slice(0, max - 1).trimEnd() + "…";
}

export function normalizeUrl(raw: string): string | null {
  try {
    const u = new URL(raw.trim());
    if (u.protocol !== "http:" && u.protocol !== "https:") return null;
    u.hash = "";
    for (const key of [...u.searchParams.keys()]) {
      if (key.toLowerCase().startsWith("utm_")) u.searchParams.delete(key);
    }
    return u.toString();
  } catch {
    return null;
  }
}

function safeDate(raw: string, now: Date): Date {
  if (!raw) return now;
  const d = new Date(raw);
  if (Number.isNaN(d.getTime()) || d > now) return now;
  return d;
}

const firstImage = (html: string): string | null =>
  html.match(/<img[^>]+src=["']([^"']+)["']/i)?.[1] ?? null;

export function parseFeed(xml: string, now: Date = new Date()): FeedItem[] {
  let doc: Node;
  try {
    doc = parser.parse(xml);
  } catch {
    throw new FeedError("XML inválido");
  }
  if (!doc?.rss && !doc?.feed && !doc?.["rdf:RDF"]) {
    throw new FeedError("não é um feed RSS/Atom");
  }
  const out: FeedItem[] = [];

  for (const it of asArray<Node>(doc.rss?.channel?.item ?? doc["rdf:RDF"]?.item)) {
    const url = normalizeUrl(text(it.link) || text(it.guid));
    const title = stripHtml(text(it.title), 300);
    if (!url || !title) continue;
    const rawDesc = text(it["content:encoded"]) || text(it.description);
    const image =
      asArray<Node>(it["media:content"])[0]?.["@_url"] ??
      asArray<Node>(it.enclosure).find((e) => String(e?.["@_type"] ?? "").startsWith("image"))?.["@_url"] ??
      asArray<Node>(it["media:thumbnail"])[0]?.["@_url"] ??
      firstImage(rawDesc);
    out.push({
      url,
      title,
      summary: stripHtml(rawDesc),
      imageUrl: image ?? null,
      publishedAt: safeDate(text(it.pubDate) || text(it["dc:date"]), now),
    });
  }

  for (const e of asArray<Node>(doc.feed?.entry)) {
    const links = asArray<Node>(e.link);
    const alt = links.find((l) => !l?.["@_rel"] || l["@_rel"] === "alternate") ?? links[0];
    const url = normalizeUrl(alt?.["@_href"] ?? text(alt));
    const title = stripHtml(text(e.title), 300);
    if (!url || !title) continue;
    const rawDesc = text(e.summary) || text(e.content);
    out.push({
      url,
      title,
      summary: stripHtml(rawDesc),
      imageUrl: firstImage(rawDesc),
      publishedAt: safeDate(text(e.published) || text(e.updated), now),
    });
  }
  return out;
}

export async function fetchFeed(url: string, fetcher: typeof fetch = fetch): Promise<FeedItem[]> {
  const res = await fetcher(url, {
    headers: { "User-Agent": USER_AGENT, Accept: "application/rss+xml, application/atom+xml, application/xml, text/xml" },
    signal: AbortSignal.timeout(10_000),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const bytes = new Uint8Array(await res.arrayBuffer());
  return parseFeed(decodeFeedBytes(bytes, res.headers.get("content-type")));
}
