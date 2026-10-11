import { z } from 'zod';
import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import type { ToolContext } from './index.js';
import {
  READ, UserError, WRITE, assertOwned, check, clampLimit, fold, normalizeTitle, ok, okData, safe, toIso,
} from './util.js';

type Row = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any

const MAX_BODY = 100_000;
const title = z.string().trim().min(1).max(200);

function noteSummary(r: Row, tz: string) {
  return { id: r.id, title: r.title, spaceId: r.space_id, updatedAt: toIso(r.updated_at, tz) };
}

export function snippet(body: string, query: string, len = 160): string {
  const flat = body.replace(/\s+/g, ' ').trim();
  if (!query) return flat.slice(0, len);
  const at = fold(flat).indexOf(fold(query));
  if (at < 0) return flat.slice(0, len);
  const start = Math.max(0, at - 40);
  return (start > 0 ? '…' : '') + flat.slice(start, start + len) + (start + len < flat.length ? '…' : '');
}

/** Cria a nota; título repetido (sem diferenciar caixa/espaços) → `null` (índice único notes_user_title_uq). */
export async function tryInsertNote(
  ctx: ToolContext, noteTitle: string, body: string, spaceId?: string | null,
): Promise<Row | null> {
  const res = await ctx.db.from('notes').insert({
    user_id: ctx.userId, title: noteTitle.trim().replace(/\s+/g, ' '), body, space_id: spaceId ?? null,
  }).select('*').single();
  if (res.error) {
    if (res.error.code === '23505') return null;
    throw Object.assign(new Error('erro do banco'), { code: res.error.code });
  }
  return res.data as Row;
}

/** Como o app (`uniqueTitle`): se o título já existe, acrescenta " 2", " 3"… */
export async function insertNoteUniqueTitle(
  ctx: ToolContext, base: string, body: string, spaceId?: string | null,
): Promise<Row> {
  for (let i = 1; i <= 50; i++) {
    const row = await tryInsertNote(ctx, i === 1 ? base : `${base} ${i}`, body, spaceId);
    if (row) return row;
  }
  throw new UserError('Não foi possível achar um título livre para a nota.');
}

async function findNote(ctx: ToolContext, ref: { id?: string; title?: string }): Promise<Row> {
  if (ref.id) {
    const r = check(await ctx.db.from('notes').select('*').eq('id', ref.id).eq('user_id', ctx.userId).maybeSingle()) as Row | null;
    if (!r) throw new UserError('Nota não encontrada.');
    return r;
  }
  if (ref.title) {
    const all = check(await ctx.db.from('notes').select('*').eq('user_id', ctx.userId).limit(5000)) as Row[];
    const key = normalizeTitle(ref.title);
    const r = all.find((n) => normalizeTitle(n.title) === key);
    if (!r) throw new UserError(`Nota "${ref.title}" não encontrada.`);
    return r;
  }
  throw new UserError('Informe o id ou o título da nota.');
}

export function registerNotes(server: McpServer, ctx: ToolContext): void {
  const tz = ctx.timeZone;

  server.registerTool('search_notes', {
    title: 'Buscar notas',
    description:
      'Busca notas por título/corpo, sem diferenciar acentos nem maiúsculas; devolve id, título e trecho. ' +
      'Informe `id` ou `title` (exato, sem diferenciar caixa/espaços) para obter uma nota com o corpo completo. ' +
      'Sem argumentos, lista as notas mais recentes.',
    inputSchema: {
      query: z.string().max(200).optional(), id: z.string().uuid().optional(), title: z.string().max(200).optional(),
      spaceId: z.string().uuid().optional(), limit: z.number().int().min(1).max(200).optional(),
    },
    annotations: READ,
  }, safe(async (a) => {
    if (a.id || a.title) {
      const n = await findNote(ctx, a);
      return okData({ note: { ...noteSummary(n, tz), parentId: n.parent_id, body: n.body } });
    }
    let q = ctx.db.from('notes').select('*').eq('user_id', ctx.userId);
    if (a.spaceId) q = q.eq('space_id', a.spaceId);
    const rows = check(await q.order('updated_at', { ascending: false }).limit(5000)) as Row[];
    const needle = fold((a.query ?? '').trim());
    const hits = needle
      ? rows.filter((n) => fold(n.title).includes(needle) || fold(n.body ?? '').includes(needle))
      : rows;
    return okData({
      notes: hits.slice(0, clampLimit(a.limit, 20)).map((n) => ({ ...noteSummary(n, tz), snippet: snippet(n.body ?? '', a.query ?? '') })),
    });
  }));

  server.registerTool('create_note', {
    title: 'Criar nota',
    description:
      'Cria uma nota. O título é único (sem diferenciar maiúsculas nem espaços extras); se já existir, a chamada falha. ' +
      'Use [[Título]] para ligar a outras notas.',
    inputSchema: {
      title, body: z.string().max(MAX_BODY).optional(), spaceId: z.string().uuid().optional(),
    },
    annotations: { ...WRITE, idempotentHint: false },
  }, safe(async (a) => {
    if (a.spaceId) await assertOwned(ctx, 'spaces', a.spaceId, 'Espaço');
    const row = await tryInsertNote(ctx, a.title, a.body ?? '', a.spaceId);
    if (!row) throw new UserError(`Já existe uma nota com o título "${a.title.trim()}" (títulos não diferenciam maiúsculas nem espaços). Escolha outro título ou use append_to_note.`);
    return ok({ note: noteSummary(row, tz) });
  }));

  server.registerTool('append_to_note', {
    title: 'Acrescentar à nota',
    description: 'Acrescenta texto ao fim de uma nota (separado por uma linha em branco), sem alterar o que já existe. Informe `id` ou `title`.',
    inputSchema: { id: z.string().uuid().optional(), title: z.string().max(200).optional(), text: z.string().min(1).max(MAX_BODY) },
    annotations: { ...WRITE, idempotentHint: false },
  }, safe(async (a) => {
    for (let attempt = 0; attempt < 5; attempt++) {
      const n = await findNote(ctx, a);
      const existing: string = n.body ?? '';
      const trimmed = existing.replace(/\s+$/, '');
      const body = trimmed ? `${trimmed}\n\n${a.text}` : a.text;
      if (body.length > MAX_BODY) throw new UserError(`A nota passaria do limite de ${MAX_BODY} caracteres.`);
      // Concorrência otimista: só grava se a nota não mudou desde a leitura.
      const rows = check(await ctx.db.from('notes').update({ body })
        .eq('id', n.id).eq('user_id', ctx.userId).eq('updated_at', n.updated_at).select('*')) as Row[];
      if (rows.length > 0) return ok({ note: { ...noteSummary(rows[0], tz), length: body.length } });
    }
    throw new UserError('A nota foi alterada por outra pessoa durante a gravação. Tente de novo.');
  }));
}
