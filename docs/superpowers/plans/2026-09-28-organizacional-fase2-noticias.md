# Organizacional — Fase 2: Notícias — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Coletar notícias de fontes confiáveis por RSS (catálogo + feeds próprios), filtrá-las pelos interesses e bloqueios configurados no app e mostrá-las numa aba Notícias e em Hoje.

**Architecture:** Uma Edge Function Deno (`news-fetch`), disparada por `pg_cron` a cada 20 minutos, baixa os feeds assinados, decodifica o charset, faz o parse de RSS/Atom e grava em `news_items`. A regra de filtragem vive numa função SQL (`news_feed`), reutilizada depois pelo app, pela ponte da Alexa (Fase 3) e pelo MCP (Fase 4). No app, uma interface `NewsRepository` (implementações em memória e Supabase) alimenta as telas.

**Tech Stack:** Supabase (Postgres, `unaccent`, `pg_cron`, `pg_net`, Vault, Edge Functions/Deno), `npm:fast-xml-parser@4.5.0`, `jsr:@std/assert@1`; Flutter + Riverpod + go_router (Fase 1), `url_launcher`.

**Spec:** `docs/superpowers/specs/2026-09-28-organizacional-design.md`
**Pré-requisito:** Fase 1 concluída (`docs/superpowers/plans/2026-09-28-organizacional-fase1-fundacao.md`). Este plano usa `RepositoryException`, `clockProvider`, `asyncView`, `SectionHeader`, `EmptyHint`, `showError`, `newId`, `parseDate`, `pumpApp` e o router da Fase 1.

## Global Constraints

- Todas as regras da Fase 1 continuam valendo: RLS por `user_id = auth.uid()`, UI em pt-BR, datas em `timestamptz` UTC, testes com `TZ=America/Sao_Paulo`, `flutter analyze` sem erros nem warnings.
- `news_sources.user_id` nulo = catálogo global (somente leitura para usuários); preenchido = feed próprio do usuário.
- `news_items` só é gravado pela Edge Function (service role); o usuário apenas lê os próprios itens.
- A filtragem acontece **só** em `public.news_feed(p_user uuid default auth.uid(), p_limit int default 50)`: termos comparados como palavra inteira (`\m...\M`), sem diferenciar maiúsculas nem acentos (`unaccent`).
- Destaques vêm primeiro; dentro de cada grupo, mais recentes primeiro.
- A Edge Function roda com `verify_jwt = false` e autoriza por `x-cron-secret` (cron) ou por um JWT de usuário válido.
- Itens com mais de 14 dias são apagados a cada coleta.
- User-Agent das requisições: `Organizacional/1.0 (+leitor pessoal de RSS)`; timeout de 10 s por feed.
- Um feed com falha nunca impede os outros de serem coletados.

## Review Focus

1. **Feed em ISO-8859-1** (Folha): os acentos têm que chegar corretos (`Eleição`, não `EleiÃ§Ã£o`). Teste `feed_test.ts` → "decodifica ISO-8859-1" (Task 1).
2. **Palavra-chave curta** ("IA"): destaca "Nova IA do Google", mas não "Dia de chuva" nem "mídia". Também vale para termos com acento contra títulos sem acento/maiúsculos. Teste `news_test.sql` (Task 2).
3. **Um feed fora do ar ou com XML quebrado** não impede os outros de serem coletados e aparece em `failures`. Teste `collect_test.ts` (Task 3).
4. **Feed próprio que não é RSS** (ex.: colar `https://g1.globo.com` em vez do feed): o app mostra um erro claro e não salva a fonte. Testes `feed_test.ts` (HTML → `FeedError`, Task 1) e `news_screens_test.dart` (Task 5).
5. **A mesma notícia em dois feeds assinados** (ex.: G1 Principais e G1 Política) aparece uma vez só. Teste `collect_test.ts` (Task 3) + constraint `unique (user_id, url)` (Task 2).

---

## Mapa de arquivos

```
supabase/
├── config.toml                                         (Modify: [functions.news-fetch])
├── migrations/20260929000000_news.sql                  tabelas, RLS, news_feed, catálogo
├── migrations/20260929000100_news_cron.sql             pg_cron → Edge Function
├── tests/database/news_test.sql
└── functions/
    ├── .env                                            (local, gitignored) CRON_SECRET
    └── news-fetch/
        ├── feed.ts            decodeFeedBytes, parseFeed, stripHtml, normalizeUrl, fetchFeed, FeedError
        ├── catalog.ts         CATALOG (espelho da lista inserida na migration)
        ├── check_feeds.ts     script: testa cada feed do catálogo
        ├── collect.ts         collect(subs, sources, fetchItems)
        ├── auth.ts            isAuthorized(req, cronSecret, getUser)
        ├── index.ts           handler HTTP (coleta ou validação de URL)
        ├── feed_test.ts, collect_test.ts, auth_test.ts
app/
├── lib/domain/news.dart                               NewsItem, NewsSource, NewsPrefs, parseTerms, timeAgo, validateFeedUrl
├── lib/data/news_repository.dart                      NewsRepository
├── lib/data/memory_news_repository.dart
├── lib/data/supabase_news_repository.dart
├── lib/ui/news_tile.dart
├── lib/features/news/news_screen.dart                 /noticias
├── lib/features/news/news_settings_screen.dart        /noticias/ajustes (+ AddFeedDialog)
├── lib/app/providers.dart                             (Modify: providers de notícias + linkOpenerProvider)
├── lib/app/router.dart                                (Modify: 2 rotas)
├── lib/features/today/today_screen.dart               (Replace: ícone Notícias + seção Manchetes)
├── lib/main.dart                                      (Replace: override do NewsRepository)
└── test/
    ├── helpers.dart                                   (Replace: pumpApp com news/openLink)
    ├── domain/news_test.dart
    ├── data/memory_news_repository_test.dart
    └── features/news_screens_test.dart
```

**Paralelização:** Task 1 ∥ Task 2 ∥ Task 4. A Task 3 depende de 1 e 2. A Task 5 depende de 4. A Task 6 fecha.

---

### Task 1: Parser de feeds (Deno) e verificação do catálogo

**Files:**
- Create: `supabase/functions/news-fetch/feed.ts`, `supabase/functions/news-fetch/catalog.ts`, `supabase/functions/news-fetch/check_feeds.ts`
- Test: `supabase/functions/news-fetch/feed_test.ts`

**Interfaces:**
- Consumes: nada.
- Produces:
  - `interface FeedItem { url: string; title: string; summary: string; imageUrl: string | null; publishedAt: Date }`
  - `class FeedError extends Error`
  - `decodeFeedBytes(bytes: Uint8Array, contentType: string | null): string`
  - `parseFeed(xml: string, now?: Date): FeedItem[]` (lança `FeedError` se não for RSS/Atom)
  - `stripHtml(html: string, max?: number): string`, `normalizeUrl(raw: string): string | null`
  - `fetchFeed(url: string, fetcher?: typeof fetch): Promise<FeedItem[]>`, `USER_AGENT`
  - `CATALOG: { name: string; section: string; feedUrl: string }[]`

- [ ] **Step 1: Instalar o Deno (se `deno --version` falhar)**

Run: `curl -fsSL https://deno.land/install.sh | sh && export PATH="$HOME/.deno/bin:$PATH" && deno --version`
Expected: `deno 2.x`.

- [ ] **Step 2: Escrever os testes**

Create `supabase/functions/news-fetch/feed_test.ts`:
```ts
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
```

- [ ] **Step 3: Rodar e ver falhar**

Run: `cd /home/only/organizacional && deno test supabase/functions/news-fetch/feed_test.ts`
Expected: FAIL com `Module not found "file:///.../feed.ts"`.

- [ ] **Step 4: Implementar o parser**

Create `supabase/functions/news-fetch/feed.ts`:
```ts
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
```

- [ ] **Step 5: Rodar e ver passar**

Run: `deno test supabase/functions/news-fetch/feed_test.ts`
Expected: `ok | 8 passed | 0 failed`.

- [ ] **Step 6: Catálogo e script de verificação**

Create `supabase/functions/news-fetch/catalog.ts`:
```ts
/** Espelho da lista inserida em supabase/migrations/20260929000000_news.sql. Mantenha os dois iguais. */
export const CATALOG: { name: string; section: string; feedUrl: string }[] = [
  { name: "G1", section: "Principais", feedUrl: "https://g1.globo.com/rss/g1/" },
  { name: "G1", section: "Política", feedUrl: "https://g1.globo.com/rss/g1/politica/" },
  { name: "G1", section: "Economia", feedUrl: "https://g1.globo.com/rss/g1/economia/" },
  { name: "G1", section: "Tecnologia", feedUrl: "https://g1.globo.com/rss/g1/tecnologia/" },
  { name: "G1", section: "Educação", feedUrl: "https://g1.globo.com/rss/g1/educacao/" },
  { name: "G1", section: "Ciência e Saúde", feedUrl: "https://g1.globo.com/rss/g1/ciencia-e-saude/" },
  { name: "Folha de S.Paulo", section: "Em cima da hora", feedUrl: "https://feeds.folha.uol.com.br/emcimadahora/rss091.xml" },
  { name: "Folha de S.Paulo", section: "Poder", feedUrl: "https://feeds.folha.uol.com.br/poder/rss091.xml" },
  { name: "Folha de S.Paulo", section: "Mercado", feedUrl: "https://feeds.folha.uol.com.br/mercado/rss091.xml" },
  { name: "Folha de S.Paulo", section: "Tec", feedUrl: "https://feeds.folha.uol.com.br/tec/rss091.xml" },
  { name: "Folha de S.Paulo", section: "Mundo", feedUrl: "https://feeds.folha.uol.com.br/mundo/rss091.xml" },
  { name: "Estadão", section: "Política", feedUrl: "https://www.estadao.com.br/arc/outboundfeeds/feeds/rss/sections/politica/" },
  { name: "Estadão", section: "Economia", feedUrl: "https://www.estadao.com.br/arc/outboundfeeds/feeds/rss/sections/economia/" },
  { name: "Estadão", section: "Brasil", feedUrl: "https://www.estadao.com.br/arc/outboundfeeds/feeds/rss/sections/brasil/" },
  { name: "O Globo", section: "Principais", feedUrl: "https://oglobo.globo.com/rss/oglobo" },
  { name: "CNN Brasil", section: "Principais", feedUrl: "https://www.cnnbrasil.com.br/feed/" },
  { name: "CNN Brasil", section: "Política", feedUrl: "https://www.cnnbrasil.com.br/politica/feed/" },
  { name: "CNN Brasil", section: "Economia", feedUrl: "https://www.cnnbrasil.com.br/economia/feed/" },
  { name: "BBC News Brasil", section: "Principais", feedUrl: "https://feeds.bbci.co.uk/portuguese/rss.xml" },
  { name: "Agência Brasil", section: "Últimas", feedUrl: "https://agenciabrasil.ebc.com.br/rss/ultimasnoticias/feed.xml" },
];
```

Create `supabase/functions/news-fetch/check_feeds.ts`:
```ts
import { CATALOG } from "./catalog.ts";
import { fetchFeed } from "./feed.ts";

let failures = 0;
for (const s of CATALOG) {
  try {
    const items = await fetchFeed(s.feedUrl);
    const status = items.length > 0 ? "OK   " : "VAZIO";
    if (items.length === 0) failures++;
    console.log(`${status} ${s.name} / ${s.section}: ${items.length} itens — ${items[0]?.title ?? ""}`);
  } catch (e) {
    failures++;
    console.log(`FALHA ${s.name} / ${s.section} (${s.feedUrl}): ${e}`);
  }
}
Deno.exit(failures === 0 ? 0 : 1);
```

- [ ] **Step 7: Verificar os feeds reais**

Run: `deno run --allow-net supabase/functions/news-fetch/check_feeds.ts`
Expected: uma linha `OK` por feed, com títulos legíveis e acentos corretos. Para cada linha `FALHA`/`VAZIO`: abra o site da fonte, procure o link "RSS" e troque a URL em `catalog.ts`. Se a fonte não tiver RSS, remova a linha. Repita até o script sair com código 0. **Anote a lista final.** A Task 2 insere exatamente essas URLs.

- [ ] **Step 8: Commit**

```bash
git add supabase/functions/news-fetch
git commit -m "feat: parser de feeds RSS/Atom com charset e catálogo verificado"
```

---

### Task 2: Schema de notícias, filtro `news_feed` e catálogo

**Files:**
- Create: `supabase/migrations/20260929000000_news.sql`
- Test: `supabase/tests/database/news_test.sql`

**Interfaces:**
- Consumes: `public.touch_updated_at()` (Fase 1).
- Produces: tabelas `news_sources(id, user_id null=catálogo, name, section, feed_url)`, `news_subscriptions(user_id, source_id)`, `news_prefs(user_id pk, keywords text[], blocked text[], max_age_hours int, briefing_count int)`, `news_items(id, user_id, source_id, url, title, summary, image_url, published_at, fetched_at)`; funções `public.news_term_match(haystack text, term text) → boolean` e `public.news_feed(p_user uuid default auth.uid(), p_limit int default 50) → table(id uuid, source_id uuid, source_name text, title text, summary text, url text, image_url text, published_at timestamptz, highlighted boolean)`.

- [ ] **Step 1: Escrever o teste pgTAP**

Create `supabase/tests/database/news_test.sql`:
```sql
begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.dev');

insert into news_sources (id, user_id, name, section, feed_url) values
  ('00000000-0000-0000-0000-0000000000a1', null, 'Teste', 'Geral', 'https://teste.dev/a.xml'),
  ('00000000-0000-0000-0000-0000000000a2', null, 'Outro', 'Geral', 'https://teste.dev/b.xml');

insert into news_items (user_id, source_id, url, title, summary, published_at) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-0000000000a1', 'https://t.dev/1', 'Nova IA do Google chega ao Brasil', '', now() - interval '1 hour'),
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-0000000000a1', 'https://t.dev/2', 'Dia de chuva em São Paulo', 'mídia relata alagamentos', now() - interval '2 hours'),
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-0000000000a1', 'https://t.dev/3', 'BBB 26: paredão', '', now() - interval '3 hours'),
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-0000000000a1', 'https://t.dev/4', 'ELEICAO municipal', '', now() - interval '4 hours'),
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-0000000000a1', 'https://t.dev/5', 'Notícia velha', '', now() - interval '5 days'),
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-0000000000a2', 'https://t.dev/6', 'Fonte não assinada', '', now() - interval '1 hour');

-- Usuário A
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true);
insert into news_subscriptions (source_id) values ('00000000-0000-0000-0000-0000000000a1');
insert into news_prefs (keywords, blocked, max_age_hours) values (array['IA', 'eleição'], array['bbb'], 48);

select is((select count(*) from news_feed())::int, 3,
  'só itens assinados, dentro da janela e não bloqueados');
select ok((select highlighted from news_feed() where url = 'https://t.dev/1'),
  '"IA" destaca "Nova IA do Google"');
select ok(not (select highlighted from news_feed() where url = 'https://t.dev/2'),
  '"IA" não destaca "Dia" nem "mídia"');
select ok((select highlighted from news_feed() where url = 'https://t.dev/4'),
  '"eleição" destaca "ELEICAO"');
select results_eq(
  'select url from news_feed()',
  $$ values ('https://t.dev/1'), ('https://t.dev/4'), ('https://t.dev/2') $$,
  'destaques primeiro, depois os mais recentes');
select lives_ok(
  $$ insert into news_sources (user_id, name, feed_url) values ('11111111-1111-1111-1111-111111111111', 'Meu blog', 'https://blog.dev/feed') $$,
  'A adiciona um feed próprio');
select throws_ok(
  $$ insert into news_sources (user_id, name, feed_url) values (null, 'Falso catálogo', 'https://x.dev/f') $$,
  '42501', null,
  'usuário não escreve no catálogo');

-- Usuário B
select set_config('request.jwt.claims', '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}', true);
select is((select count(*) from news_feed())::int, 0, 'B não vê as notícias de A');
select is((select count(*) from news_sources where name = 'Meu blog')::int, 0, 'B não vê o feed próprio de A');

select * from finish();
rollback;
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `npx supabase test db`
Expected: FAIL em `news_test.sql` com `relation "news_sources" does not exist`.

- [ ] **Step 3: Escrever a migration**

Create `supabase/migrations/20260929000000_news.sql` (se a Task 1 mudou o catálogo, ajuste o `insert` final para ficar igual a `catalog.ts`):
```sql
create extension if not exists unaccent with schema extensions;

create table public.news_sources (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users (id) on delete cascade, -- null = catálogo
  name text not null check (length(btrim(name)) > 0),
  section text not null default 'Geral',
  feed_url text not null check (feed_url ~ '^https?://'),
  created_at timestamptz not null default now(),
  unique nulls not distinct (user_id, feed_url)
);

create table public.news_subscriptions (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  source_id uuid not null references public.news_sources (id) on delete cascade,
  primary key (user_id, source_id)
);

create table public.news_prefs (
  user_id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  keywords text[] not null default '{}',
  blocked text[] not null default '{}',
  max_age_hours integer not null default 48 check (max_age_hours between 1 and 336),
  briefing_count integer not null default 3 check (briefing_count between 0 and 10),
  updated_at timestamptz not null default now()
);
create trigger touch_updated_at before update on public.news_prefs
  for each row execute function public.touch_updated_at();

create table public.news_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  source_id uuid not null references public.news_sources (id) on delete cascade,
  url text not null,
  title text not null,
  summary text not null default '',
  image_url text,
  published_at timestamptz not null,
  fetched_at timestamptz not null default now(),
  unique (user_id, url)
);
create index news_items_recent_idx on public.news_items (user_id, published_at desc);

alter table public.news_sources enable row level security;
alter table public.news_subscriptions enable row level security;
alter table public.news_prefs enable row level security;
alter table public.news_items enable row level security;

create policy "catálogo ou próprio" on public.news_sources for select to authenticated
  using (user_id is null or user_id = (select auth.uid()));
create policy "insere próprio" on public.news_sources for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "altera próprio" on public.news_sources for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "apaga próprio" on public.news_sources for delete to authenticated
  using (user_id = (select auth.uid()));
create policy "dono" on public.news_subscriptions for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "dono" on public.news_prefs for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "lê próprio" on public.news_items for select to authenticated
  using (user_id = (select auth.uid()));

create or replace function public.news_term_match(haystack text, term text)
returns boolean
language sql
stable
set search_path = ''
as $$
  select length(btrim(term)) > 0
     and haystack ~ (
       '\m'
       || regexp_replace(
            lower(extensions.unaccent('extensions.unaccent'::regdictionary, btrim(term))),
            '([.^$*+?()\[\]{}|\\-])', '\\\1', 'g')
       || '\M');
$$;

create or replace function public.news_feed(p_user uuid default auth.uid(), p_limit integer default 50)
returns table (
  id uuid, source_id uuid, source_name text, title text, summary text,
  url text, image_url text, published_at timestamptz, highlighted boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
  with prefs as (
    select coalesce(p.keywords, '{}') as keywords,
           coalesce(p.blocked, '{}') as blocked,
           coalesce(p.max_age_hours, 48) as max_age
    from (select 1) as one
    left join public.news_prefs p on p.user_id = p_user
  ),
  items as (
    select i.*, s.name as source_name,
           lower(extensions.unaccent('extensions.unaccent'::regdictionary, i.title || ' ' || i.summary)) as haystack
    from public.news_items i
    join public.news_subscriptions sub on sub.source_id = i.source_id and sub.user_id = p_user
    join public.news_sources s on s.id = i.source_id
    where i.user_id = p_user
      and i.published_at >= now() - make_interval(hours => (select max_age from prefs))
  )
  select i.id, i.source_id, i.source_name, i.title, i.summary, i.url, i.image_url, i.published_at,
         exists (select 1 from unnest((select keywords from prefs)) k where public.news_term_match(i.haystack, k)) as highlighted
  from items i
  where not exists (select 1 from unnest((select blocked from prefs)) b where public.news_term_match(i.haystack, b))
  order by highlighted desc, i.published_at desc
  limit p_limit;
$$;

insert into public.news_sources (user_id, name, section, feed_url) values
  (null, 'G1', 'Principais', 'https://g1.globo.com/rss/g1/'),
  (null, 'G1', 'Política', 'https://g1.globo.com/rss/g1/politica/'),
  (null, 'G1', 'Economia', 'https://g1.globo.com/rss/g1/economia/'),
  (null, 'G1', 'Tecnologia', 'https://g1.globo.com/rss/g1/tecnologia/'),
  (null, 'G1', 'Educação', 'https://g1.globo.com/rss/g1/educacao/'),
  (null, 'G1', 'Ciência e Saúde', 'https://g1.globo.com/rss/g1/ciencia-e-saude/'),
  (null, 'Folha de S.Paulo', 'Em cima da hora', 'https://feeds.folha.uol.com.br/emcimadahora/rss091.xml'),
  (null, 'Folha de S.Paulo', 'Poder', 'https://feeds.folha.uol.com.br/poder/rss091.xml'),
  (null, 'Folha de S.Paulo', 'Mercado', 'https://feeds.folha.uol.com.br/mercado/rss091.xml'),
  (null, 'Folha de S.Paulo', 'Tec', 'https://feeds.folha.uol.com.br/tec/rss091.xml'),
  (null, 'Folha de S.Paulo', 'Mundo', 'https://feeds.folha.uol.com.br/mundo/rss091.xml'),
  (null, 'Estadão', 'Política', 'https://www.estadao.com.br/arc/outboundfeeds/feeds/rss/sections/politica/'),
  (null, 'Estadão', 'Economia', 'https://www.estadao.com.br/arc/outboundfeeds/feeds/rss/sections/economia/'),
  (null, 'Estadão', 'Brasil', 'https://www.estadao.com.br/arc/outboundfeeds/feeds/rss/sections/brasil/'),
  (null, 'O Globo', 'Principais', 'https://oglobo.globo.com/rss/oglobo'),
  (null, 'CNN Brasil', 'Principais', 'https://www.cnnbrasil.com.br/feed/'),
  (null, 'CNN Brasil', 'Política', 'https://www.cnnbrasil.com.br/politica/feed/'),
  (null, 'CNN Brasil', 'Economia', 'https://www.cnnbrasil.com.br/economia/feed/'),
  (null, 'BBC News Brasil', 'Principais', 'https://feeds.bbci.co.uk/portuguese/rss.xml'),
  (null, 'Agência Brasil', 'Últimas', 'https://agenciabrasil.ebc.com.br/rss/ultimasnoticias/feed.xml');
```

- [ ] **Step 4: Aplicar e rodar os testes**

Run: `npx supabase db reset && npx supabase test db`
Expected: PASS em `core_test.sql` (8) e `news_test.sql` (9).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260929000000_news.sql supabase/tests/database/news_test.sql
git commit -m "feat: schema de notícias com filtro por interesses e bloqueios"
```

---

### Task 3: Edge Function `news-fetch` (coleta, validação de feed e cron)

**Files:**
- Create: `supabase/functions/news-fetch/collect.ts`, `supabase/functions/news-fetch/auth.ts`, `supabase/functions/news-fetch/index.ts`
- Create: `supabase/migrations/20260929000100_news_cron.sql`
- Modify: `supabase/config.toml` (append), `.gitignore` (append)
- Test: `supabase/functions/news-fetch/collect_test.ts`, `supabase/functions/news-fetch/auth_test.ts`

**Interfaces:**
- Consumes: `FeedItem`, `fetchFeed`, `FeedError` (Task 1); tabelas da Task 2.
- Produces:
  - `collect(subs: Subscription[], sources: SourceRow[], fetchItems: (url: string) => Promise<FeedItem[]>): Promise<{ rows: ItemRow[]; failures: { source: string; error: string }[] }>`
  - `isAuthorized(req: Request, cronSecret: string | undefined, getUser: (jwt: string) => Promise<boolean>): Promise<boolean>`
  - HTTP `POST /functions/v1/news-fetch`, com corpo `{}` → `{ sources, items, failures }` e corpo `{ "validate": "<url>" }` → `{ ok: true, count, sample }` ou `{ ok: false, error }`. Responde `401` sem autorização.

- [ ] **Step 1: Escrever os testes**

Create `supabase/functions/news-fetch/collect_test.ts`:
```ts
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
```

Create `supabase/functions/news-fetch/auth_test.ts`:
```ts
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
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `deno test supabase/functions/news-fetch/`
Expected: FAIL (`collect.ts` e `auth.ts` não existem).

- [ ] **Step 3: Implementar a coleta, a autorização e o handler**

Create `supabase/functions/news-fetch/collect.ts`:
```ts
import type { FeedItem } from "./feed.ts";

export interface SourceRow { id: string; name: string; feed_url: string }
export interface Subscription { user_id: string; source_id: string }
export interface ItemRow {
  user_id: string;
  source_id: string;
  url: string;
  title: string;
  summary: string;
  image_url: string | null;
  published_at: string;
}

export async function collect(
  subs: Subscription[],
  sources: SourceRow[],
  fetchItems: (url: string) => Promise<FeedItem[]>,
): Promise<{ rows: ItemRow[]; failures: { source: string; error: string }[] }> {
  const byId = new Map(sources.map((s) => [s.id, s]));
  const ids = [...new Set(subs.map((s) => s.source_id))].filter((id) => byId.has(id));
  const results = await Promise.allSettled(
    ids.map(async (id) => ({ id, items: await fetchItems(byId.get(id)!.feed_url) })),
  );

  const rows: ItemRow[] = [];
  const seen = new Set<string>();
  const failures: { source: string; error: string }[] = [];
  results.forEach((result, index) => {
    if (result.status === "rejected") {
      const reason = result.reason;
      failures.push({
        source: byId.get(ids[index])!.name,
        error: reason instanceof Error ? reason.message : String(reason),
      });
      return;
    }
    const { id, items } = result.value;
    for (const sub of subs.filter((s) => s.source_id === id)) {
      for (const it of items) {
        const key = `${sub.user_id} ${it.url}`;
        if (seen.has(key)) continue;
        seen.add(key);
        rows.push({
          user_id: sub.user_id,
          source_id: id,
          url: it.url,
          title: it.title,
          summary: it.summary,
          image_url: it.imageUrl,
          published_at: it.publishedAt.toISOString(),
        });
      }
    }
  });
  return { rows, failures };
}
```

Create `supabase/functions/news-fetch/auth.ts`:
```ts
export async function isAuthorized(
  req: Request,
  cronSecret: string | undefined,
  getUser: (jwt: string) => Promise<boolean>,
): Promise<boolean> {
  if (cronSecret && req.headers.get("x-cron-secret") === cronSecret) return true;
  const header = req.headers.get("authorization") ?? "";
  const jwt = header.startsWith("Bearer ") ? header.slice("Bearer ".length) : "";
  if (!jwt) return false;
  try {
    return await getUser(jwt);
  } catch {
    return false;
  }
}
```

Create `supabase/functions/news-fetch/index.ts`:
```ts
import { createClient } from "npm:@supabase/supabase-js@2";
import { isAuthorized } from "./auth.ts";
import { collect } from "./collect.ts";
import { FeedError, fetchFeed } from "./feed.ts";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const RETENTION_MS = 14 * 24 * 60 * 60 * 1000;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

const getUser = async (jwt: string) => {
  const { data, error } = await db.auth.getUser(jwt);
  return !error && !!data.user;
};

Deno.serve(async (req) => {
  if (!(await isAuthorized(req, Deno.env.get("CRON_SECRET"), getUser))) {
    return json({ error: "não autorizado" }, 401);
  }
  const body = await req.json().catch(() => ({}));

  if (typeof body.validate === "string") {
    try {
      const items = await fetchFeed(body.validate);
      return json({ ok: true, count: items.length, sample: items[0]?.title ?? null });
    } catch (e) {
      return json({ ok: false, error: e instanceof FeedError ? e.message : `não foi possível baixar: ${e}` });
    }
  }

  const [subsRes, sourcesRes] = await Promise.all([
    db.from("news_subscriptions").select("user_id, source_id"),
    db.from("news_sources").select("id, name, feed_url"),
  ]);
  if (subsRes.error || sourcesRes.error) {
    return json({ error: (subsRes.error ?? sourcesRes.error)!.message }, 500);
  }
  const subs = subsRes.data ?? [];
  const { rows, failures } = await collect(subs, sourcesRes.data ?? [], (url) => fetchFeed(url));

  for (let i = 0; i < rows.length; i += 500) {
    const { error } = await db
      .from("news_items")
      .upsert(rows.slice(i, i + 500), { onConflict: "user_id,url", ignoreDuplicates: true });
    if (error) return json({ error: error.message }, 500);
  }
  await db.from("news_items").delete().lt("published_at", new Date(Date.now() - RETENTION_MS).toISOString());

  return json({ sources: new Set(subs.map((s) => s.source_id)).size, items: rows.length, failures });
});
```

- [ ] **Step 4: Rodar os testes Deno**

Run: `deno test supabase/functions/news-fetch/`
Expected: `ok | 15 passed | 0 failed` (8 do feed + 3 da coleta + 4 da autorização).

- [ ] **Step 5: Configuração, segredo local e cron**

Append to `supabase/config.toml`:
```toml

[functions.news-fetch]
verify_jwt = false
```

Append to `.gitignore`:
```
supabase/functions/.env
```

Create `supabase/functions/.env`:
```
CRON_SECRET=segredo-local-de-desenvolvimento
```

Create `supabase/migrations/20260929000100_news_cron.sql`:
```sql
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

-- Os segredos ficam no Vault (Task 6): 'news_fetch_url' e 'cron_secret'.
-- Sem eles o job roda, mas a requisição falha sem efeito.
select cron.schedule(
  'news-fetch',
  '*/20 * * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'news_fetch_url'),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
    ),
    body := '{}'::jsonb
  );
  $$
);
```

- [ ] **Step 6: Testar a função localmente de ponta a ponta**

Run (terminal 1): `npx supabase db reset && npx supabase functions serve news-fetch --env-file supabase/functions/.env`
Run (terminal 2):
```bash
DB_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres
psql "$DB_URL" -c "insert into auth.users (id, email) values ('11111111-1111-1111-1111-111111111111','eu@local.dev') on conflict do nothing;
insert into news_subscriptions (user_id, source_id) select '11111111-1111-1111-1111-111111111111', id from news_sources where name = 'G1' and section = 'Principais';"
curl -s -X POST http://127.0.0.1:54321/functions/v1/news-fetch -H 'x-cron-secret: segredo-local-de-desenvolvimento' -H 'Content-Type: application/json' -d '{}'
curl -s -X POST http://127.0.0.1:54321/functions/v1/news-fetch -H 'x-cron-secret: segredo-local-de-desenvolvimento' -H 'Content-Type: application/json' -d '{"validate":"https://g1.globo.com"}'
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:54321/functions/v1/news-fetch -d '{}'
psql "$DB_URL" -c "select count(*) from news_items;"
```
Expected: 1º curl `{"sources":1,"items":<n>,"failures":[]}` com n > 0; 2º `{"ok":false,"error":"não é um feed RSS/Atom"}` (ou `XML inválido`); 3º `401`; o `count` > 0. Se `psql` não estiver instalado: `sudo apt-get install -y postgresql-client`.

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/news-fetch supabase/migrations/20260929000100_news_cron.sql supabase/config.toml .gitignore
git commit -m "feat: edge function news-fetch com coleta, validação de feed e cron"
```

---

### Task 4: Domínio e repositórios de notícias no app

**Files:**
- Create: `app/lib/domain/news.dart`, `app/lib/data/news_repository.dart`, `app/lib/data/memory_news_repository.dart`, `app/lib/data/supabase_news_repository.dart`
- Test: `app/test/domain/news_test.dart`, `app/test/data/memory_news_repository_test.dart`

**Interfaces:**
- Consumes: `parseDate` (`domain/json.dart`), `newId` (`domain/ids.dart`), `RepositoryException` (`data/repository.dart`), da Fase 1; RPC `news_feed` e Edge Function `news-fetch` (Tasks 2–3).
- Produces:
  - `class NewsItem({required String id, String sourceId = '', required String sourceName, required String title, String summary = '', required String url, String? imageUrl, required DateTime publishedAt, bool highlighted = false})` + `fromMap`
  - `class NewsSource({required String id, required String name, required String section, required String feedUrl, bool custom = false, bool subscribed = false})` + `copyWith({bool? subscribed})`
  - `class NewsPrefs({List<String> keywords = const [], List<String> blocked = const [], int maxAgeHours = 48, int briefingCount = 3})` + `fromMap`, `toMap`, `==`
  - `List<String> parseTerms(String input)`, `String timeAgo(DateTime t, DateTime now)`, `String? validateFeedUrl(String input)`
  - `abstract interface class NewsRepository { Future<List<NewsItem>> feed({int limit = 50}); Future<List<NewsSource>> sources(); Future<void> setSubscribed(String sourceId, bool subscribed); Future<NewsSource> addCustomSource({required String name, required String feedUrl}); Future<void> deleteCustomSource(String id); Future<NewsPrefs> prefs(); Future<void> savePrefs(NewsPrefs prefs); Future<void> refreshNow(); }`
  - `class MemoryNewsRepository({List<NewsSource> sources, List<NewsItem> items, Set<String> validFeeds})` com `bool failWrites`, `int refreshCount`
  - `class SupabaseNewsRepository(SupabaseClient db)`

- [ ] **Step 1: Escrever os testes**

Create `app/test/domain/news_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/domain/news.dart';

void main() {
  test('parseTerms separa por vírgula, ponto e vírgula e linha, sem duplicatas', () {
    expect(parseTerms(' IA, clima;  Copa do   Mundo\nia , ,'), ['IA', 'clima', 'Copa do Mundo']);
    expect(parseTerms('   '), isEmpty);
  });

  test('timeAgo', () {
    final now = DateTime(2026, 9, 28, 12);
    expect(timeAgo(now.add(const Duration(minutes: 5)), now), 'agora');
    expect(timeAgo(now.subtract(const Duration(seconds: 30)), now), 'agora');
    expect(timeAgo(now.subtract(const Duration(minutes: 7)), now), 'há 7 min');
    expect(timeAgo(now.subtract(const Duration(hours: 3)), now), 'há 3 h');
    expect(timeAgo(now.subtract(const Duration(hours: 30)), now), 'ontem');
    expect(timeAgo(now.subtract(const Duration(days: 4)), now), 'há 4 dias');
  });

  test('validateFeedUrl', () {
    expect(validateFeedUrl('https://blog.dev/feed'), isNull);
    expect(validateFeedUrl('  http://a.dev/rss.xml '), isNull);
    expect(validateFeedUrl('blog.dev/feed'), 'Informe um endereço http(s) válido.');
    expect(validateFeedUrl('ftp://a.dev/x'), 'Informe um endereço http(s) válido.');
  });

  test('NewsItem.fromMap lê a linha do news_feed', () {
    final item = NewsItem.fromMap({
      'id': 'i1',
      'source_id': 's1',
      'source_name': 'G1',
      'title': 'Manchete',
      'summary': null,
      'url': 'https://g1/x',
      'image_url': null,
      'published_at': '2026-09-28T13:00:00+00:00',
      'highlighted': true,
    });
    expect(item.summary, '');
    expect(item.highlighted, isTrue);
    expect(item.publishedAt.toUtc(), DateTime.utc(2026, 9, 28, 13));
  });

  test('NewsPrefs ida e volta', () {
    const prefs = NewsPrefs(keywords: ['IA'], blocked: ['BBB'], maxAgeHours: 24, briefingCount: 5);
    expect(NewsPrefs.fromMap(prefs.toMap()), prefs);
  });
}
```

Create `app/test/data/memory_news_repository_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_news_repository.dart';
import 'package:organizacional/data/repository.dart';
import 'package:organizacional/domain/news.dart';

void main() {
  final t = DateTime(2026, 9, 28, 10);
  NewsItem item(String id, String sourceId, {bool highlighted = false, int hoursAgo = 1}) => NewsItem(
        id: id,
        sourceId: sourceId,
        sourceName: sourceId,
        title: id,
        url: 'https://x/$id',
        publishedAt: t.subtract(Duration(hours: hoursAgo)),
        highlighted: highlighted,
      );

  test('feed mostra só fontes assinadas, destaques primeiro', () async {
    final repo = MemoryNewsRepository(
      sources: const [
        NewsSource(id: 'g1', name: 'G1', section: 'Principais', feedUrl: 'https://g1', subscribed: true),
        NewsSource(id: 'folha', name: 'Folha', section: 'Poder', feedUrl: 'https://folha'),
      ],
      items: [
        item('recente', 'g1', hoursAgo: 1),
        item('destaque', 'g1', highlighted: true, hoursAgo: 5),
        item('nao-assinada', 'folha'),
      ],
    );
    expect((await repo.feed()).map((i) => i.id), ['destaque', 'recente']);
    await repo.setSubscribed('folha', true);
    expect((await repo.feed()).length, 3);
  });

  test('feed próprio: URL inválida, não-feed e sucesso', () async {
    final repo = MemoryNewsRepository(validFeeds: {'https://blog.dev/feed'});
    await expectLater(
      repo.addCustomSource(name: 'Blog', feedUrl: 'blog.dev'),
      throwsA(isA<RepositoryException>()
          .having((e) => e.message, 'message', 'Informe um endereço http(s) válido.')),
    );
    await expectLater(
      repo.addCustomSource(name: 'Site', feedUrl: 'https://g1.globo.com'),
      throwsA(isA<RepositoryException>()
          .having((e) => e.message, 'message', startsWith('Esse endereço não é um feed RSS/Atom'))),
    );
    final added = await repo.addCustomSource(name: 'Blog', feedUrl: 'https://blog.dev/feed');
    expect(added.custom, isTrue);
    expect(added.subscribed, isTrue);
    expect((await repo.sources()).single.name, 'Blog');
  });

  test('preferências salvas voltam iguais; failWrites simula queda', () async {
    final repo = MemoryNewsRepository();
    const prefs = NewsPrefs(keywords: ['IA']);
    await repo.savePrefs(prefs);
    expect(await repo.prefs(), prefs);
    repo.failWrites = true;
    await expectLater(repo.savePrefs(const NewsPrefs()), throwsA(isA<RepositoryException>()));
  });
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd app && TZ=America/Sao_Paulo flutter test test/domain/news_test.dart test/data/memory_news_repository_test.dart`
Expected: FAIL (arquivos não existem).

- [ ] **Step 3: Implementar o domínio**

Create `app/lib/domain/news.dart`:
```dart
import 'package:flutter/foundation.dart';

import 'json.dart';

class NewsItem {
  const NewsItem({
    required this.id,
    this.sourceId = '',
    required this.sourceName,
    required this.title,
    this.summary = '',
    required this.url,
    this.imageUrl,
    required this.publishedAt,
    this.highlighted = false,
  });

  final String id;
  final String sourceId;
  final String sourceName;
  final String title;
  final String summary;
  final String url;
  final String? imageUrl;
  final DateTime publishedAt;
  final bool highlighted;

  factory NewsItem.fromMap(Map<String, dynamic> m) => NewsItem(
        id: m['id'] as String,
        sourceId: (m['source_id'] as String?) ?? '',
        sourceName: m['source_name'] as String,
        title: m['title'] as String,
        summary: (m['summary'] as String?) ?? '',
        url: m['url'] as String,
        imageUrl: m['image_url'] as String?,
        publishedAt: parseDate(m['published_at'])!,
        highlighted: (m['highlighted'] as bool?) ?? false,
      );
}

class NewsSource {
  const NewsSource({
    required this.id,
    required this.name,
    required this.section,
    required this.feedUrl,
    this.custom = false,
    this.subscribed = false,
  });

  final String id;
  final String name;
  final String section;
  final String feedUrl;
  final bool custom;
  final bool subscribed;

  NewsSource copyWith({bool? subscribed}) => NewsSource(
        id: id,
        name: name,
        section: section,
        feedUrl: feedUrl,
        custom: custom,
        subscribed: subscribed ?? this.subscribed,
      );
}

class NewsPrefs {
  const NewsPrefs({
    this.keywords = const [],
    this.blocked = const [],
    this.maxAgeHours = 48,
    this.briefingCount = 3,
  });

  final List<String> keywords;
  final List<String> blocked;
  final int maxAgeHours;
  final int briefingCount;

  factory NewsPrefs.fromMap(Map<String, dynamic> m) => NewsPrefs(
        keywords: ((m['keywords'] as List?) ?? const []).cast<String>(),
        blocked: ((m['blocked'] as List?) ?? const []).cast<String>(),
        maxAgeHours: (m['max_age_hours'] as num?)?.toInt() ?? 48,
        briefingCount: (m['briefing_count'] as num?)?.toInt() ?? 3,
      );

  Map<String, dynamic> toMap() => {
        'keywords': keywords,
        'blocked': blocked,
        'max_age_hours': maxAgeHours,
        'briefing_count': briefingCount,
      };

  @override
  bool operator ==(Object other) =>
      other is NewsPrefs &&
      listEquals(other.keywords, keywords) &&
      listEquals(other.blocked, blocked) &&
      other.maxAgeHours == maxAgeHours &&
      other.briefingCount == briefingCount;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(keywords), Object.hashAll(blocked), maxAgeHours, briefingCount);
}

List<String> parseTerms(String input) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in input.split(RegExp(r'[,;\n]'))) {
    final term = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (term.isEmpty) continue;
    if (seen.add(term.toLowerCase())) out.add(term);
  }
  return out;
}

String timeAgo(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return 'agora';
  if (d.inMinutes < 60) return 'há ${d.inMinutes} min';
  if (d.inHours < 24) return 'há ${d.inHours} h';
  if (d.inDays == 1) return 'ontem';
  return 'há ${d.inDays} dias';
}

String? validateFeedUrl(String input) {
  final uri = Uri.tryParse(input.trim());
  final ok = uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
  return ok ? null : 'Informe um endereço http(s) válido.';
}
```

- [ ] **Step 4: Implementar os repositórios**

Create `app/lib/data/news_repository.dart`:
```dart
import '../domain/news.dart';

abstract interface class NewsRepository {
  Future<List<NewsItem>> feed({int limit = 50});
  Future<List<NewsSource>> sources();
  Future<void> setSubscribed(String sourceId, bool subscribed);

  /// Valida o feed antes de salvar; lança RepositoryException com mensagem para o usuário.
  Future<NewsSource> addCustomSource({required String name, required String feedUrl});
  Future<void> deleteCustomSource(String id);
  Future<NewsPrefs> prefs();
  Future<void> savePrefs(NewsPrefs prefs);

  /// Pede ao servidor uma coleta imediata.
  Future<void> refreshNow();
}
```

Create `app/lib/data/memory_news_repository.dart`:
```dart
import '../domain/ids.dart';
import '../domain/news.dart';
import 'news_repository.dart';
import 'repository.dart';

/// Implementação em memória para testes. `highlighted` vem pronto nos itens.
class MemoryNewsRepository implements NewsRepository {
  MemoryNewsRepository({
    List<NewsSource> sources = const [],
    List<NewsItem> items = const [],
    this.validFeeds = const {},
  })  : _sources = [...sources],
        _items = [...items];

  final List<NewsSource> _sources;
  final List<NewsItem> _items;
  final Set<String> validFeeds;
  NewsPrefs _prefs = const NewsPrefs();
  bool failWrites = false;
  int refreshCount = 0;

  void _checkWrite() {
    if (failWrites) throw const RepositoryException('Sem conexão (simulado)');
  }

  @override
  Future<List<NewsItem>> feed({int limit = 50}) async {
    final subscribed = {for (final s in _sources) if (s.subscribed) s.id};
    final list = _items.where((i) => subscribed.contains(i.sourceId)).toList()
      ..sort((a, b) {
        if (a.highlighted != b.highlighted) return a.highlighted ? -1 : 1;
        return b.publishedAt.compareTo(a.publishedAt);
      });
    return list.take(limit).toList();
  }

  @override
  Future<List<NewsSource>> sources() async => List.of(_sources);

  @override
  Future<void> setSubscribed(String sourceId, bool subscribed) async {
    _checkWrite();
    final i = _sources.indexWhere((s) => s.id == sourceId);
    if (i >= 0) _sources[i] = _sources[i].copyWith(subscribed: subscribed);
  }

  @override
  Future<NewsSource> addCustomSource({required String name, required String feedUrl}) async {
    _checkWrite();
    final problem = validateFeedUrl(feedUrl);
    if (problem != null) throw RepositoryException(problem);
    if (!validFeeds.contains(feedUrl.trim())) {
      throw const RepositoryException('Esse endereço não é um feed RSS/Atom.');
    }
    final source = NewsSource(
      id: newId(),
      name: name.trim(),
      section: 'Personalizada',
      feedUrl: feedUrl.trim(),
      custom: true,
      subscribed: true,
    );
    _sources.add(source);
    return source;
  }

  @override
  Future<void> deleteCustomSource(String id) async {
    _checkWrite();
    _sources.removeWhere((s) => s.id == id && s.custom);
  }

  @override
  Future<NewsPrefs> prefs() async => _prefs;

  @override
  Future<void> savePrefs(NewsPrefs prefs) async {
    _checkWrite();
    _prefs = prefs;
  }

  @override
  Future<void> refreshNow() async {
    _checkWrite();
    refreshCount++;
  }
}
```

Create `app/lib/data/supabase_news_repository.dart`:
```dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/news.dart';
import 'news_repository.dart';
import 'repository.dart';

class SupabaseNewsRepository implements NewsRepository {
  SupabaseNewsRepository(this._db);

  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on PostgrestException catch (e) {
      throw RepositoryException(e.message, duplicate: e.code == '23505');
    } on FunctionException catch (e) {
      throw RepositoryException('Falha ao chamar o servidor (${e.status}).');
    } on RepositoryException {
      rethrow;
    } catch (e) {
      throw RepositoryException('Falha de conexão: $e');
    }
  }

  @override
  Future<List<NewsItem>> feed({int limit = 50}) => _guard(() async {
        final rows = await _db.rpc('news_feed', params: {'p_limit': limit}) as List<dynamic>;
        return rows.map((r) => NewsItem.fromMap(r as Map<String, dynamic>)).toList();
      });

  @override
  Future<List<NewsSource>> sources() => _guard(() async {
        final rows = await _db
            .from('news_sources')
            .select('id, name, section, feed_url, user_id')
            .order('name')
            .order('section');
        final subs = await _db.from('news_subscriptions').select('source_id');
        final subscribed = {for (final s in subs) s['source_id'] as String};
        return [
          for (final r in rows)
            NewsSource(
              id: r['id'] as String,
              name: r['name'] as String,
              section: r['section'] as String,
              feedUrl: r['feed_url'] as String,
              custom: r['user_id'] != null,
              subscribed: subscribed.contains(r['id']),
            ),
        ];
      });

  @override
  Future<void> setSubscribed(String sourceId, bool subscribed) => _guard(() async {
        if (subscribed) {
          await _db
              .from('news_subscriptions')
              .upsert({'source_id': sourceId}, onConflict: 'user_id,source_id', ignoreDuplicates: true);
        } else {
          await _db.from('news_subscriptions').delete().eq('source_id', sourceId);
        }
      });

  @override
  Future<NewsSource> addCustomSource({required String name, required String feedUrl}) =>
      _guard(() async {
        final problem = validateFeedUrl(feedUrl);
        if (problem != null) throw RepositoryException(problem);
        final url = feedUrl.trim();
        final res = await _db.functions.invoke('news-fetch', body: {'validate': url});
        final data = (res.data as Map).cast<String, dynamic>();
        if (data['ok'] != true) {
          throw RepositoryException('Esse endereço não é um feed RSS/Atom (${data['error']}).');
        }
        final row = await _db
            .from('news_sources')
            .insert({
              'user_id': _db.auth.currentUser!.id,
              'name': name.trim(),
              'section': 'Personalizada',
              'feed_url': url,
            })
            .select()
            .single();
        await _db.from('news_subscriptions').insert({'source_id': row['id']});
        return NewsSource(
          id: row['id'] as String,
          name: row['name'] as String,
          section: 'Personalizada',
          feedUrl: url,
          custom: true,
          subscribed: true,
        );
      });

  @override
  Future<void> deleteCustomSource(String id) =>
      _guard(() async => await _db.from('news_sources').delete().eq('id', id));

  @override
  Future<NewsPrefs> prefs() => _guard(() async {
        final row = await _db.from('news_prefs').select().maybeSingle();
        return row == null ? const NewsPrefs() : NewsPrefs.fromMap(row);
      });

  @override
  Future<void> savePrefs(NewsPrefs prefs) =>
      _guard(() async => await _db.from('news_prefs').upsert(prefs.toMap()));

  @override
  Future<void> refreshNow() =>
      _guard(() async => await _db.functions.invoke('news-fetch', body: const {}));
}
```

- [ ] **Step 5: Rodar e ver passar**

Run: `TZ=America/Sao_Paulo flutter test --exclude-tags integration && flutter analyze`
Expected: `All tests passed!`; sem erros nem warnings.

- [ ] **Step 6: Commit**

```bash
git add app/lib/domain/news.dart app/lib/data/news_repository.dart app/lib/data/memory_news_repository.dart app/lib/data/supabase_news_repository.dart app/test/domain/news_test.dart app/test/data/memory_news_repository_test.dart
git commit -m "feat: domínio e repositórios de notícias"
```

---

### Task 5: Telas de notícias, manchetes em Hoje e rotas

**Files:**
- Create: `app/lib/ui/news_tile.dart`, `app/lib/features/news/news_screen.dart`, `app/lib/features/news/news_settings_screen.dart`
- Modify: `app/lib/app/providers.dart`, `app/lib/app/router.dart`
- Replace: `app/lib/features/today/today_screen.dart`, `app/lib/main.dart`, `app/test/helpers.dart`
- Test: `app/test/features/news_screens_test.dart`

**Interfaces:**
- Consumes: Task 4 inteira; da Fase 1, `repositoryProvider`, `clockProvider`, `spacesProvider`, `tasksProvider`, `eventsFromProvider`, `asyncView`, `SectionHeader`, `EmptyHint`, `showError`, `TaskTile`, `EventTile`, `buildDayAgenda`, `startOfDay`, `OrganizacionalApp`, `buildRouter`, `StreamListenable`, `SupabaseRepository`.
- Produces:
  - Providers: `newsRepositoryProvider` (`Provider<NewsRepository>`), `newsFeedProvider` (`FutureProvider<List<NewsItem>>`), `newsSourcesProvider`, `newsPrefsProvider`, `linkOpenerProvider` (`Provider<Future<void> Function(Uri)>`)
  - Rotas `/noticias` → `NewsScreen`, `/noticias/ajustes` → `NewsSettingsScreen` (dentro do shell; a navegação destaca "Hoje")
  - Keys: `open-news` (ícone em Hoje), `refresh-news`, `news-settings`, `news-keywords`, `news-blocked`, `save-news-prefs`, `add-feed`, `feed-name`, `feed-url`, `source-<id>`
  - `pumpApp(tester, repo, {location, now, size, NewsRepository? news, Future<void> Function(Uri)? openLink})`

- [ ] **Step 1: Atualizar o helper de testes e escrever os testes**

Replace all of `app/test/helpers.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/app/app.dart';
import 'package:organizacional/app/providers.dart';
import 'package:organizacional/app/router.dart';
import 'package:organizacional/data/memory_news_repository.dart';
import 'package:organizacional/data/news_repository.dart';
import 'package:organizacional/data/repository.dart';

final defaultNow = DateTime(2026, 9, 28, 10); // segunda-feira

Future<void> pumpApp(
  WidgetTester tester,
  Repository repo, {
  String location = '/',
  DateTime? now,
  Size size = const Size(1000, 800),
  NewsRepository? news,
  Future<void> Function(Uri)? openLink,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      clockProvider.overrideWithValue(() => now ?? defaultNow),
      newsRepositoryProvider.overrideWithValue(news ?? MemoryNewsRepository()),
      linkOpenerProvider.overrideWithValue(openLink ?? (_) async {}),
    ],
    child: OrganizacionalApp(
      router: buildRouter(initialLocation: location, isSignedIn: () => true),
    ),
  ));
  await tester.pumpAndSettle();
}
```

Create `app/test/features/news_screens_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/data/memory_news_repository.dart';
import 'package:organizacional/data/memory_repository.dart';
import 'package:organizacional/domain/news.dart';

import '../helpers.dart';

final _now = DateTime(2026, 9, 28, 10);

MemoryNewsRepository _news() => MemoryNewsRepository(
      sources: const [
        NewsSource(id: 'g1', name: 'G1', section: 'Principais', feedUrl: 'https://g1', subscribed: true),
        NewsSource(id: 'folha', name: 'Folha de S.Paulo', section: 'Poder', feedUrl: 'https://folha'),
      ],
      items: [
        NewsItem(
          id: 'n1',
          sourceId: 'g1',
          sourceName: 'G1',
          title: 'Chuva forte em BH',
          url: 'https://g1/chuva',
          publishedAt: _now.subtract(const Duration(hours: 2)),
        ),
        NewsItem(
          id: 'n2',
          sourceId: 'g1',
          sourceName: 'G1',
          title: 'Nova IA brasileira',
          summary: 'Pesquisadores apresentam modelo.',
          url: 'https://g1/ia',
          publishedAt: _now.subtract(const Duration(hours: 5)),
          highlighted: true,
        ),
      ],
      validFeeds: {'https://blog.dev/feed'},
    );

void main() {
  testWidgets('lista notícias com destaque primeiro e abre o link', (tester) async {
    final opened = <Uri>[];
    await pumpApp(tester, MemoryRepository(),
        location: '/noticias', now: _now, news: _news(), openLink: (u) async => opened.add(u));
    final ia = tester.getTopLeft(find.text('Nova IA brasileira'));
    final chuva = tester.getTopLeft(find.text('Chuva forte em BH'));
    expect(ia.dy, lessThan(chuva.dy));
    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(find.textContaining('G1 · há 2 h'), findsOneWidget);
    await tester.tap(find.text('Chuva forte em BH'));
    await tester.pump();
    expect(opened, [Uri.parse('https://g1/chuva')]);
  });

  testWidgets('sem notícias mostra atalho para escolher fontes', (tester) async {
    await pumpApp(tester, MemoryRepository(), location: '/noticias');
    await tester.tap(find.text('Escolher fontes'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Fontes e interesses'), findsOneWidget);
  });

  testWidgets('atualizar pede coleta ao servidor', (tester) async {
    final news = _news();
    await pumpApp(tester, MemoryRepository(), location: '/noticias', news: news);
    await tester.tap(find.byKey(const Key('refresh-news')));
    await tester.pumpAndSettle();
    expect(news.refreshCount, 1);
  });

  testWidgets('assinar fonte e salvar interesses', (tester) async {
    final news = _news();
    await pumpApp(tester, MemoryRepository(),
        location: '/noticias/ajustes', news: news, size: const Size(1000, 1600));
    await tester.tap(find.byKey(const ValueKey('source-folha')));
    await tester.pumpAndSettle();
    expect((await news.sources()).firstWhere((s) => s.id == 'folha').subscribed, isTrue);

    await tester.enterText(find.byKey(const Key('news-keywords')), 'IA, UFMG;  clima');
    await tester.enterText(find.byKey(const Key('news-blocked')), 'BBB');
    await tester.tap(find.text('7 dias'));
    await tester.tap(find.byKey(const Key('save-news-prefs')));
    await tester.pumpAndSettle();
    final prefs = await news.prefs();
    expect(prefs.keywords, ['IA', 'UFMG', 'clima']);
    expect(prefs.blocked, ['BBB']);
    expect(prefs.maxAgeHours, 168);
    expect(find.text('Preferências salvas.'), findsOneWidget);
  });

  testWidgets('feed próprio que não é RSS mostra erro e não é salvo', (tester) async {
    final news = _news();
    await pumpApp(tester, MemoryRepository(),
        location: '/noticias/ajustes', news: news, size: const Size(1000, 1600));
    await tester.tap(find.byKey(const Key('add-feed')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('feed-name')), 'G1 site');
    await tester.enterText(find.byKey(const Key('feed-url')), 'https://g1.globo.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Adicionar'));
    await tester.pumpAndSettle();
    expect(find.text('Esse endereço não é um feed RSS/Atom.'), findsOneWidget);
    expect((await news.sources()).length, 2);

    await tester.tap(find.byKey(const Key('add-feed')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('feed-name')), 'Meu blog');
    await tester.enterText(find.byKey(const Key('feed-url')), 'https://blog.dev/feed');
    await tester.tap(find.widgetWithText(FilledButton, 'Adicionar'));
    await tester.pumpAndSettle();
    expect(find.text('Meu blog'), findsOneWidget);
  });

  testWidgets('Hoje mostra manchetes e o ícone abre Notícias', (tester) async {
    await pumpApp(tester, MemoryRepository(), now: _now, news: _news());
    expect(find.text('Manchetes'), findsOneWidget);
    expect(find.text('Nova IA brasileira'), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-news')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Notícias'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `cd app && flutter pub add url_launcher && TZ=America/Sao_Paulo flutter test test/features/news_screens_test.dart`
Expected: FAIL (`newsRepositoryProvider` não definido).

- [ ] **Step 3: Providers e rotas**

Modify `app/lib/app/providers.dart`, adding these imports at the top:
```dart
import 'package:url_launcher/url_launcher.dart';

import '../data/news_repository.dart';
import '../domain/news.dart';
```
and appending at the end of the file:
```dart
final newsRepositoryProvider = Provider<NewsRepository>(
  (ref) => throw UnimplementedError('newsRepositoryProvider precisa de override'),
);

final newsFeedProvider =
    FutureProvider<List<NewsItem>>((ref) => ref.watch(newsRepositoryProvider).feed());

final newsSourcesProvider =
    FutureProvider<List<NewsSource>>((ref) => ref.watch(newsRepositoryProvider).sources());

final newsPrefsProvider =
    FutureProvider<NewsPrefs>((ref) => ref.watch(newsRepositoryProvider).prefs());

final linkOpenerProvider = Provider<Future<void> Function(Uri)>(
  (ref) => (uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  },
);
```

Modify `app/lib/app/router.dart`: add the imports
```dart
import '../features/news/news_screen.dart';
import '../features/news/news_settings_screen.dart';
```
and, inside the `ShellRoute` `routes: [...]`, after the `/nota/:id` route:
```dart
            GoRoute(path: '/noticias', builder: (context, state) => const NewsScreen()),
            GoRoute(
              path: '/noticias/ajustes',
              builder: (context, state) => const NewsSettingsScreen(),
            ),
```

- [ ] **Step 4: Tile e tela de notícias**

Create `app/lib/ui/news_tile.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../domain/news.dart';

class NewsTile extends ConsumerWidget {
  const NewsTile({super.key, required this.item});

  final NewsItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = ref.watch(clockProvider)();
    final meta = '${item.sourceName} · ${timeAgo(item.publishedAt, now)}';
    return ListTile(
      leading: item.highlighted
          ? Icon(Icons.star, color: theme.colorScheme.primary, semanticLabel: 'Destaque')
          : null,
      title: Text(
        item.title,
        style: item.highlighted ? const TextStyle(fontWeight: FontWeight.w600) : null,
      ),
      subtitle: Text(
        item.summary.isEmpty ? meta : '$meta\n${item.summary}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: item.summary.isNotEmpty,
      onTap: () => ref.read(linkOpenerProvider)(Uri.parse(item.url)),
    );
  }
}
```

Create `app/lib/features/news/news_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../ui/common.dart';
import '../../ui/news_tile.dart';

class NewsScreen extends ConsumerWidget {
  const NewsScreen({super.key});

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(newsRepositoryProvider).refreshNow();
    } on RepositoryException {
      if (context.mounted) showError(context, 'Não foi possível buscar notícias agora.');
    }
    ref.invalidate(newsFeedProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(newsFeedProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notícias'),
        actions: [
          IconButton(
            key: const Key('refresh-news'),
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () => _refresh(context, ref),
          ),
          IconButton(
            key: const Key('news-settings'),
            tooltip: 'Fontes e interesses',
            icon: const Icon(Icons.tune),
            onPressed: () => context.go('/noticias/ajustes'),
          ),
        ],
      ),
      body: asyncView(feed, (items) {
        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const EmptyHint('Nenhuma notícia ainda.'),
                TextButton(
                  onPressed: () => context.go('/noticias/ajustes'),
                  child: const Text('Escolher fontes'),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () => _refresh(context, ref),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) => NewsTile(key: ValueKey(items[i].id), item: items[i]),
          ),
        );
      }),
    );
  }
}
```

- [ ] **Step 5: Tela de ajustes**

Create `app/lib/features/news/news_settings_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repository.dart';
import '../../domain/news.dart';
import '../../ui/common.dart';

class NewsSettingsScreen extends ConsumerStatefulWidget {
  const NewsSettingsScreen({super.key});

  @override
  ConsumerState<NewsSettingsScreen> createState() => _NewsSettingsScreenState();
}

class _NewsSettingsScreenState extends ConsumerState<NewsSettingsScreen> {
  final _keywords = TextEditingController();
  final _blocked = TextEditingController();
  int _maxAge = 48;
  int _briefing = 3;
  bool _loaded = false;

  static const _ages = [(24, '24 horas'), (48, '2 dias'), (168, '7 dias')];
  static const _briefings = [(0, 'Nenhuma'), (3, '3'), (5, '5')];

  @override
  void dispose() {
    _keywords.dispose();
    _blocked.dispose();
    super.dispose();
  }

  void _refreshFeed() {
    ref.invalidate(newsSourcesProvider);
    ref.invalidate(newsFeedProvider);
  }

  Future<void> _toggle(NewsSource source, bool subscribed) async {
    try {
      await ref.read(newsRepositoryProvider).setSubscribed(source.id, subscribed);
      _refreshFeed();
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível alterar a fonte.');
    }
  }

  Future<void> _save() async {
    final prefs = NewsPrefs(
      keywords: parseTerms(_keywords.text),
      blocked: parseTerms(_blocked.text),
      maxAgeHours: _maxAge,
      briefingCount: _briefing,
    );
    try {
      await ref.read(newsRepositoryProvider).savePrefs(prefs);
      ref.invalidate(newsPrefsProvider);
      ref.invalidate(newsFeedProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Preferências salvas.')));
      }
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível salvar as preferências.');
    }
  }

  Future<void> _addFeed() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const AddFeedDialog(),
    );
    if (result == null) return;
    final (name, url) = result;
    try {
      await ref.read(newsRepositoryProvider).addCustomSource(name: name, feedUrl: url);
      _refreshFeed();
    } on RepositoryException catch (e) {
      if (mounted) showError(context, e.message);
    }
  }

  Future<void> _delete(NewsSource source) async {
    try {
      await ref.read(newsRepositoryProvider).deleteCustomSource(source.id);
      _refreshFeed();
    } on RepositoryException {
      if (mounted) showError(context, 'Não foi possível remover o feed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(newsPrefsProvider);
    final sources = ref.watch(newsSourcesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Fontes e interesses')),
      body: asyncView(prefs, (p) {
        if (!_loaded) {
          _loaded = true;
          _keywords.text = p.keywords.join(', ');
          _blocked.text = p.blocked.join(', ');
          _maxAge = p.maxAgeHours;
          _briefing = p.briefingCount;
        }
        return asyncView(sources, (list) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SectionHeader('Interesses'),
                TextField(
                  key: const Key('news-keywords'),
                  controller: _keywords,
                  decoration: const InputDecoration(
                    labelText: 'Destacar notícias sobre',
                    helperText: 'Separe por vírgula. Ex.: inteligência artificial, Copa, UFMG',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('news-blocked'),
                  controller: _blocked,
                  decoration: const InputDecoration(labelText: 'Esconder notícias sobre'),
                ),
                const SectionHeader('Mostrar notícias de até'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (hours, label) in _ages)
                      ChoiceChip(
                        label: Text(label),
                        selected: _maxAge == hours,
                        onSelected: (_) => setState(() => _maxAge = hours),
                      ),
                  ],
                ),
                const SectionHeader('Manchetes no resumo da Alexa'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (count, label) in _briefings)
                      ChoiceChip(
                        label: Text(label),
                        selected: _briefing == count,
                        onSelected: (_) => setState(() => _briefing = count),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    key: const Key('save-news-prefs'),
                    onPressed: _save,
                    child: const Text('Salvar preferências'),
                  ),
                ),
                Row(
                  children: [
                    const Expanded(child: SectionHeader('Fontes')),
                    TextButton.icon(
                      key: const Key('add-feed'),
                      onPressed: _addFeed,
                      icon: const Icon(Icons.add),
                      label: const Text('Adicionar feed'),
                    ),
                  ],
                ),
                for (final s in list)
                  SwitchListTile(
                    key: ValueKey('source-${s.id}'),
                    title: Text(s.name),
                    subtitle: Text(s.section),
                    value: s.subscribed,
                    onChanged: (v) => _toggle(s, v),
                    secondary: s.custom
                        ? IconButton(
                            tooltip: 'Remover feed',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(s),
                          )
                        : null,
                  ),
              ],
            ));
      }),
    );
  }
}

class AddFeedDialog extends StatefulWidget {
  const AddFeedDialog({super.key});

  @override
  State<AddFeedDialog> createState() => _AddFeedDialogState();
}

class _AddFeedDialogState extends State<AddFeedDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _name.text.trim().isNotEmpty && _url.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('Adicionar feed'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('feed-name'),
            controller: _name,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Nome'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('feed-url'),
            controller: _url,
            keyboardType: TextInputType.url,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Endereço do feed RSS',
              hintText: 'https://site.com/feed',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: ready
              ? () => Navigator.of(context).pop((_name.text.trim(), _url.text.trim()))
              : null,
          child: const Text('Adicionar'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 6: Manchetes em Hoje e override no main**

Replace all of `app/lib/features/today/today_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../domain/agenda.dart';
import '../../domain/news.dart';
import '../../ui/common.dart';
import '../../ui/event_tile.dart';
import '../../ui/news_tile.dart';
import '../../ui/task_tile.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final events = ref.watch(eventsFromProvider(startOfDay(now)));
    final tasks = ref.watch(tasksProvider);
    final spaces = ref.watch(spacesProvider);
    final headlines = (ref.watch(newsFeedProvider).value ?? const <NewsItem>[]).take(3).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(now)),
        actions: [
          IconButton(
            key: const Key('open-news'),
            tooltip: 'Notícias',
            icon: const Icon(Icons.newspaper_outlined),
            onPressed: () => context.go('/noticias'),
          ),
        ],
      ),
      body: asyncView(events, (eventList) => asyncView(tasks, (taskList) {
            final names = {for (final s in spaces.value ?? const []) s.id: s.name};
            final agenda = buildDayAgenda(now: now, events: eventList, tasks: taskList);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SectionHeader('Aulas e eventos'),
                if (agenda.events.isEmpty) const EmptyHint('Nada na agenda hoje.'),
                for (final e in agenda.events) EventTile(event: e, spaceName: names[e.spaceId]),
                if (agenda.overdue.isNotEmpty) ...[
                  const SectionHeader('Atrasadas'),
                  for (final t in agenda.overdue)
                    TaskTile(key: ValueKey(t.id), task: t, spaceName: names[t.spaceId]),
                ],
                const SectionHeader('Para hoje'),
                if (agenda.dueToday.isEmpty) const EmptyHint('Nenhuma tarefa para hoje.'),
                for (final t in agenda.dueToday)
                  TaskTile(key: ValueKey(t.id), task: t, spaceName: names[t.spaceId]),
                if (headlines.isNotEmpty) ...[
                  const SectionHeader('Manchetes'),
                  for (final n in headlines) NewsTile(key: ValueKey('news-${n.id}'), item: n),
                ],
              ],
            );
          })),
    );
  }
}
```

Replace all of `app/lib/main.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'app/router.dart';
import 'data/supabase_news_repository.dart';
import 'data/supabase_repository.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  if (_supabaseUrl.isEmpty || _supabaseKey.isEmpty) {
    runApp(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Configure SUPABASE_URL e SUPABASE_ANON_KEY (veja app/env.example.json).'),
        ),
      ),
    ));
    return;
  }
  await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseKey);
  final client = Supabase.instance.client;
  final router = buildRouter(
    isSignedIn: () => client.auth.currentSession != null,
    refresh: StreamListenable(client.auth.onAuthStateChange),
  );
  runApp(ProviderScope(
    overrides: [
      repositoryProvider.overrideWithValue(SupabaseRepository(client)),
      newsRepositoryProvider.overrideWithValue(SupabaseNewsRepository(client)),
    ],
    child: OrganizacionalApp(router: router),
  ));
}
```

- [ ] **Step 7: Rodar e ver passar (inclui os testes da Fase 1)**

Run: `TZ=America/Sao_Paulo flutter test --exclude-tags integration && flutter analyze`
Expected: `All tests passed!`; sem erros nem warnings. Se `separatorBuilder: (_, _)` der erro de parâmetro duplicado (Dart < 3.7), troque por `(context, index)`.

- [ ] **Step 8: Teste manual contra o Supabase local**

Run: `npx supabase functions serve news-fetch --env-file supabase/functions/.env` (terminal separado) e `cd app && flutter run -d linux --dart-define-from-file=env.json`
Expected: em Notícias → ⚙, ligue "G1 / Principais", volte e toque em ↻: as manchetes aparecem. Coloque um interesse que esteja em alguma manchete e salve: ela sobe com ★. Adicionar `https://g1.globo.com` como feed mostra o erro.

- [ ] **Step 9: Commit**

```bash
cd /home/only/organizacional
git add app
git commit -m "feat: aba Notícias, ajustes de fontes e interesses e manchetes em Hoje"
```

---

### Task 6: Deploy na nuvem e verificação

**Files:**
- Modify: `README.md` (seção Notícias)

**Interfaces:**
- Consumes: tudo acima.
- Produces: função `news-fetch` publicada; job `news-fetch` do `pg_cron` rodando a cada 20 min.

- [ ] **Step 1: Suítes verdes**

Run:
```bash
cd /home/only/organizacional
npx supabase test db
deno test supabase/functions/news-fetch/
cd app && TZ=America/Sao_Paulo flutter test --exclude-tags integration && flutter analyze
```
Expected: tudo PASS.

- [ ] **Step 2: Publicar migrations, função e segredos**

Run:
```bash
cd /home/only/organizacional
SEGREDO=$(openssl rand -hex 24)
npx supabase db push
npx supabase functions deploy news-fetch
npx supabase secrets set CRON_SECRET="$SEGREDO"
echo "$SEGREDO"   # use no próximo passo
```
Expected: `Deployed Functions ... news-fetch`.

No **SQL Editor** do painel do Supabase (troque `<ref>` e `<segredo>`):
```sql
select vault.create_secret('https://<ref>.supabase.co/functions/v1/news-fetch', 'news_fetch_url');
select vault.create_secret('<segredo>', 'cron_secret');
```

- [ ] **Step 3: Verificar a coleta agendada**

Ligue algumas fontes no app (build de produção), espere até 20 minutos e rode no SQL Editor:
```sql
select status, return_message, start_time from cron.job_run_details order by start_time desc limit 3;
select count(*), max(fetched_at) from news_items;
select status_code, content from net._http_response order by created desc limit 3;
```
Expected: `succeeded`; `count` > 0; resposta HTTP 200 com `"failures":[]` (ou só as fontes que caíram naquele momento).

- [ ] **Step 4: Documentar e commitar**

Append to `README.md`:
````markdown

## Notícias
- Coleta: Edge Function `news-fetch` (a cada 20 min via `pg_cron`); testes com `deno test supabase/functions/news-fetch/`.
- Verificar o catálogo de feeds: `deno run --allow-net supabase/functions/news-fetch/check_feeds.ts`.
- Local: `npx supabase functions serve news-fetch --env-file supabase/functions/.env` (`CRON_SECRET` nesse arquivo).
- Nuvem: segredos `news_fetch_url` e `cron_secret` no Vault; `npx supabase secrets set CRON_SECRET=...`.
- Filtro (interesses/bloqueios): função SQL `news_feed`. É a mesma regra usada pelo app, pela Alexa e pelo Claude.
````

```bash
git add README.md
git commit -m "docs: operação do conector de notícias"
```
