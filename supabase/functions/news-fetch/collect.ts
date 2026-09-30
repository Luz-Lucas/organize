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
