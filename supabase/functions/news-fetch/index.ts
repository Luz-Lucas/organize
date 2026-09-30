import { createClient } from "npm:@supabase/supabase-js@2";
import { isAuthorized } from "./auth.ts";
import { collect } from "./collect.ts";
import { FeedError, fetchFeed, normalizeUrl } from "./feed.ts";

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
    const url = normalizeUrl(body.validate);
    if (!url) return json({ ok: false, error: "endereço inválido (use http ou https)" });
    try {
      const items = await fetchFeed(url);
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
