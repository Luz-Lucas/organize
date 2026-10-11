import { z } from 'zod';
import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import type { ToolContext } from './index.js';
import { AVISO_DADOS, READ, WRITE, check, clampLimit, cleanExternal as clean, ddmmyyyy, ok, okData, safeHttpUrl, safe, toIso } from './util.js';
import { insertNoteUniqueTitle } from './notes.js';

type Row = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any

async function feed(ctx: ToolContext, limit: number): Promise<Row[]> {
  // news_feed filtra por p_user (a chave de serviço ignora RLS, então passamos o usuário explicitamente).
  return check(await ctx.db.rpc('news_feed', { p_user: ctx.userId, p_limit: limit })) as Row[];
}

export function registerNews(server: McpServer, ctx: ToolContext): void {
  const tz = ctx.timeZone;

  server.registerTool('list_news', {
    title: 'Listar notícias',
    description: `Manchetes das fontes assinadas, com as mesmas regras do app (palavras-chave, bloqueios, idade máxima). ${AVISO_DADOS}`,
    inputSchema: { limit: z.number().int().min(1).max(200).optional() },
    annotations: { ...READ, openWorldHint: true },
  }, safe(async (a) => {
    const rows = await feed(ctx, clampLimit(a.limit, 20));
    return okData({
      news: rows.map((r) => ({
        id: r.id, source: r.source_name, title: r.title, summary: r.summary, url: r.url,
        publishedAt: toIso(r.published_at, tz), highlighted: r.highlighted,
      })),
    });
  }));

  server.registerTool('create_news_digest', {
    title: 'Criar resumo de notícias',
    description: 'Cria a nota "Notícias — dd/MM/yyyy" com as principais manchetes (se o título do dia já existir, acrescenta um número).',
    inputSchema: { limit: z.number().int().min(1).max(50).optional() },
    annotations: { ...WRITE, idempotentHint: false },
  }, safe(async (a) => {
    const rows = await feed(ctx, clampLimit(a.limit, 10, 50));
    const lines = rows.map((r) => {
      const summary = clean(r.summary ?? '');
      const url = safeHttpUrl(r.url);
      return `- **${clean(r.title)}** (${clean(r.source_name)})${summary ? ` — ${summary}` : ''}${url ? ` ${url}` : ''}`;
    });
    const body = lines.length ? lines.join('\n') : 'Nenhuma manchete disponível no momento.';
    const note = await insertNoteUniqueTitle(ctx, `Notícias — ${ddmmyyyy(ctx.now(), tz)}`, body);
    return ok({ note: { id: note.id, title: note.title }, items: rows.length });
  }));
}
