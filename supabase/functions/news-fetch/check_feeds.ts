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
