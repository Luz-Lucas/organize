import { z } from 'zod';
import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import type { ToolContext } from './index.js';
import { READ, UserError, WRITE, check, clampLimit, ok, okData, parseWhen, safe, toIso } from './util.js';

type Row = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any

function noticeOut(r: Row, tz: string) {
  return {
    id: r.id, title: r.title, body: r.body, priority: r.priority, pinned: r.pinned,
    expiresAt: toIso(r.expires_at, tz), archivedAt: toIso(r.archived_at, tz), createdAt: toIso(r.created_at, tz),
  };
}

export function registerNotices(server: McpServer, ctx: ToolContext): void {
  const tz = ctx.timeZone;

  server.registerTool('list_notices', {
    title: 'Listar avisos',
    description: 'Lista os avisos ativos do quadro (sem arquivados nem expirados): fixados, depois prioridade alta, depois os mais recentes.',
    inputSchema: { limit: z.number().int().min(1).max(200).optional() },
    annotations: READ,
  }, safe(async (a) => {
    const nowIso = ctx.now().toISOString();
    const rows = check(await ctx.db.from('notices').select('*').eq('user_id', ctx.userId)
      .is('archived_at', null).or(`expires_at.is.null,expires_at.gt.${nowIso}`).limit(1000)) as Row[];
    rows.sort((x, y) => {
      if (x.pinned !== y.pinned) return x.pinned ? -1 : 1;
      if (x.priority !== y.priority) return x.priority === 'alta' ? -1 : 1;
      return Date.parse(y.created_at) - Date.parse(x.created_at);
    });
    return okData({ notices: rows.slice(0, clampLimit(a.limit)).map((r) => noticeOut(r, tz)) });
  }));

  server.registerTool('create_notice', {
    title: 'Criar aviso',
    description: 'Cria um aviso no quadro de avisos. `expiresAt` opcional (ISO 8601).',
    inputSchema: {
      title: z.string().trim().min(1).max(200), body: z.string().max(10_000).optional(),
      priority: z.enum(['normal', 'alta']).optional(), pinned: z.boolean().optional(),
      expiresAt: z.string().min(8).max(40).optional(),
    },
    annotations: { ...WRITE, idempotentHint: false },
  }, safe(async (a) => {
    const row = check(await ctx.db.from('notices').insert({
      user_id: ctx.userId, title: a.title, body: a.body ?? '', priority: a.priority ?? 'normal',
      pinned: a.pinned ?? false, expires_at: a.expiresAt ? parseWhen(a.expiresAt, tz).toISOString() : null,
    }).select('*').single());
    return ok({ notice: noticeOut(row as Row, tz) });
  }));

  server.registerTool('archive_notice', {
    title: 'Arquivar aviso',
    description: 'Arquiva um aviso (ele sai do quadro, mas não é apagado).',
    inputSchema: { id: z.string().uuid() },
    annotations: { ...WRITE, idempotentHint: true },
  }, safe(async (a) => {
    const rows = check(await ctx.db.from('notices').update({ archived_at: ctx.now().toISOString() })
      .eq('id', a.id).eq('user_id', ctx.userId).select('*')) as Row[];
    if (rows.length === 0) throw new UserError('Aviso não encontrado.');
    return ok({ notice: noticeOut(rows[0], tz) });
  }));
}
