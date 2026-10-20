import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import type { ToolContext } from './index.js';
import {
  DESTRUCTIVE, READ, UserError, WRITE, assertOwned, check, clampLimit, ok, okData, parseWhen, safe, toIso,
} from './util.js';
import { expandRepeat, normalizeRepeat, repeatSchema } from './recurrence.js';

type Row = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any

const title = z.string().trim().min(1).max(200);
const status = z.enum(['todo', 'doing', 'done']);
const priority = z.enum(['baixa', 'media', 'alta']);
const when = z.string().min(8).max(40);
const scopeSchema = z.enum(['one', 'following', 'all']).optional();

export function taskOut(r: Row, tz: string) {
  return {
    id: r.id, title: r.title, description: r.description, status: r.status, priority: r.priority,
    dueAt: toIso(r.due_at, tz), completedAt: toIso(r.completed_at, tz), spaceId: r.space_id, noteId: r.note_id,
    seriesId: r.series_id ?? null, recurrence: r.recurrence ?? null,
  };
}

/** Data e hora locais ("AAAA-MM-DD", "HH:MM") de um instante. */
function localParts(d: Date, tz: string): { date: string; time: string } {
  const l = toIso(d, tz)!;
  return { date: l.slice(0, 10), time: l.slice(11, 16) };
}

/** Soma `days` dias a uma data "AAAA-MM-DD". */
function addDays(date: string, days: number): string {
  const [y, m, d] = date.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10);
}

const dayNumber = (date: string) => Date.parse(`${date}T00:00:00Z`) / 86_400_000;

/**
 * Para cada série, o id da pendente (não concluída) de menor prazo: é a que o app mostra nas listas.
 * Lê só as colunas necessárias, em páginas, porque o PostgREST limita as respostas.
 */
async function nextPendingIds(ctx: ToolContext): Promise<Set<string>> {
  const heads = new Map<string, { id: string; due: number }>();
  const page = 1000;
  for (let from = 0; ; from += page) {
    const rows = check(await ctx.db.from('tasks').select('id, series_id, due_at').eq('user_id', ctx.userId)
      .neq('status', 'done').not('series_id', 'is', null)
      .order('id', { ascending: true }).range(from, from + page - 1)) as Row[];
    for (const r of rows) {
      const due = r.due_at ? Date.parse(r.due_at) : Number.MAX_SAFE_INTEGER;
      const cur = heads.get(r.series_id);
      if (!cur || due < cur.due) heads.set(r.series_id, { id: r.id, due });
    }
    if (rows.length < page) break;
  }
  return new Set([...heads.values()].map((h) => h.id));
}

const RANK: Record<string, number> = { doing: 0, todo: 1, done: 2 };

export function registerTasks(server: McpServer, ctx: ToolContext): void {
  const tz = ctx.timeZone;
  const parseDue = (s: string) => parseWhen(s, tz, [23, 59, 0]);

  server.registerTool('list_tasks', {
    title: 'Listar tarefas',
    description:
      'Lista tarefas ordenadas: em andamento, a fazer, depois concluídas; dentro de cada grupo por prazo (sem prazo por último). ' +
      'Sem `status`, as concluídas ficam de fora (peça `status: "done"` para vê-las) e de cada tarefa recorrente ' +
      '(mesmo `seriesId`) aparece só a próxima pendente, a de menor prazo; com `status`, lista todas as ocorrências.',
    inputSchema: {
      status: status.optional(), priority: priority.optional().describe('Só tarefas com esta prioridade'),
      dueBefore: when.optional().describe('Só tarefas com prazo até esta data/hora'),
      spaceId: z.string().uuid().optional(), limit: z.number().int().min(1).max(200).optional(),
    },
    annotations: READ,
  }, safe(async (a) => {
    let q = ctx.db.from('tasks').select('*').eq('user_id', ctx.userId);
    q = a.status ? q.eq('status', a.status) : q.neq('status', 'done');
    if (a.priority) q = q.eq('priority', a.priority);
    if (a.spaceId) q = q.eq('space_id', a.spaceId);
    if (a.dueBefore) q = q.not('due_at', 'is', null).lte('due_at', parseDue(a.dueBefore).toISOString());
    let rows = check(await q.limit(2000)) as Row[];
    if (!a.status && rows.some((r) => r.series_id)) {
      const next = await nextPendingIds(ctx);
      rows = rows.filter((r) => !r.series_id || next.has(r.id));
    }
    const far = Number.MAX_SAFE_INTEGER;
    rows.sort((x, y) => {
      if (RANK[x.status] !== RANK[y.status]) return RANK[x.status] - RANK[y.status];
      if (x.status === 'done') return (y.completed_at ? Date.parse(y.completed_at) : 0) - (x.completed_at ? Date.parse(x.completed_at) : 0);
      const dx = x.due_at ? Date.parse(x.due_at) : far;
      const dy = y.due_at ? Date.parse(y.due_at) : far;
      return dx - dy || String(x.title).localeCompare(String(y.title));
    });
    return okData({ tasks: rows.slice(0, clampLimit(a.limit)).map((r) => taskOut(r, tz)) });
  }));

  server.registerTool('create_task', {
    title: 'Criar tarefa',
    description:
      'Cria uma tarefa. `dueAt` aceita só data (vale até 23:59 desse dia). `priority`: baixa, media (padrão) ou alta. ' +
      'Com `repeat` (exige `dueAt`, de onde a repetição parte), cria uma série: uma tarefa por ocorrência, todas com o mesmo ' +
      '`seriesId`; `status` vale só para a primeira (as demais começam "todo") e não pode ser "done". ' +
      'Nas listas aparece só a próxima pendente de cada série.',
    inputSchema: {
      title, description: z.string().max(10_000).optional(), status: status.optional(), priority: priority.optional(),
      dueAt: when.optional(), spaceId: z.string().uuid().optional(), noteId: z.string().uuid().optional(),
      repeat: repeatSchema.optional(),
    },
    annotations: { ...WRITE, idempotentHint: false },
  }, safe(async (a) => {
    if (a.spaceId) await assertOwned(ctx, 'spaces', a.spaceId, 'Espaço');
    if (a.noteId) await assertOwned(ctx, 'notes', a.noteId, 'Nota');
    const st = a.status ?? 'todo';
    if (a.repeat) {
      if (!a.dueAt) throw new UserError('Para repetir, informe o prazo (`dueAt`): a repetição parte dele.');
      if (st === 'done') throw new UserError('Uma tarefa recorrente não pode ser criada já concluída.');
      const first = parseDue(a.dueAt);
      const rule = normalizeRepeat(a.repeat, first, tz);
      const seriesId = randomUUID();
      const rows = expandRepeat(first, rule, tz).map((d, i) => ({
        user_id: ctx.userId, title: a.title, description: a.description ?? '', status: i === 0 ? st : 'todo',
        priority: a.priority ?? 'media', due_at: d.toISOString(), completed_at: null,
        space_id: a.spaceId ?? null, note_id: a.noteId ?? null, source: 'manual', series_id: seriesId, recurrence: rule,
      }));
      if (rows.length === 0) throw new UserError('A repetição não gera nenhuma ocorrência no período.');
      const created = check(await ctx.db.from('tasks').insert(rows).select('*').order('due_at', { ascending: true })) as Row[];
      return ok({
        task: taskOut(created[0], tz), seriesId, occurrences: created.length,
        lastDueAt: toIso(created[created.length - 1].due_at, tz),
      });
    }
    const row = check(await ctx.db.from('tasks').insert({
      user_id: ctx.userId, title: a.title, description: a.description ?? '', status: st, priority: a.priority ?? 'media',
      due_at: a.dueAt ? parseDue(a.dueAt).toISOString() : null,
      completed_at: st === 'done' ? ctx.now().toISOString() : null,
      space_id: a.spaceId ?? null, note_id: a.noteId ?? null, source: 'manual',
    }).select('*').single());
    return ok({ task: taskOut(row as Row, tz) });
  }));

  server.registerTool('update_task', {
    title: 'Editar tarefa',
    description:
      'Edita uma tarefa. Mudar `status` para "done" registra a conclusão; sair de "done" a limpa. ' +
      '`dueAt: null` remove o prazo. `priority`: baixa, media ou alta. ' +
      'Em tarefa de série, `scope` escolhe o alcance de título, descrição, prioridade, prazo e espaço: `one` (padrão, só esta; ' +
      'ao editar esses campos ela sai da série), `following` (esta e as seguintes; a partir da 2ª ocorrência viram uma série nova) ' +
      'ou `all` (a série inteira). Em `following`/`all`, um novo `dueAt` desloca o dia e a hora de todas as afetadas e ' +
      '`dueAt: null` é recusado. `status` e `noteId` valem sempre só para esta tarefa (marcar como feita não sai da série).',
    inputSchema: {
      id: z.string().uuid(), title: title.optional(), description: z.string().max(10_000).optional(),
      status: status.optional(), priority: priority.optional(), dueAt: when.nullable().optional(),
      spaceId: z.string().uuid().nullable().optional(), noteId: z.string().uuid().nullable().optional(),
      scope: scopeSchema,
    },
    annotations: { ...WRITE, idempotentHint: true },
  }, safe(async (a) => {
    const scope = a.scope ?? 'one';
    const cur = check(await ctx.db.from('tasks').select('*').eq('id', a.id).eq('user_id', ctx.userId).maybeSingle()) as Row | null;
    if (!cur) throw new UserError('Tarefa não encontrada.');
    const wide = scope !== 'one' && !!cur.series_id; // altera várias ocorrências
    if (wide && a.dueAt === null) throw new UserError('Uma série precisa de prazo: não dá para remover o prazo de várias ocorrências.');
    // Campos que valem para o alcance escolhido (`shared`) e os que valem só para esta tarefa (`own`).
    const shared: Row = {};
    const own: Row = {};
    if (a.title !== undefined) shared.title = a.title;
    if (a.description !== undefined) shared.description = a.description;
    if (a.priority !== undefined) shared.priority = a.priority;
    if (a.dueAt !== undefined && !wide) shared.due_at = a.dueAt === null ? null : parseDue(a.dueAt).toISOString();
    if (a.spaceId !== undefined) {
      if (a.spaceId) await assertOwned(ctx, 'spaces', a.spaceId, 'Espaço');
      shared.space_id = a.spaceId;
    }
    if (a.noteId !== undefined) {
      if (a.noteId) await assertOwned(ctx, 'notes', a.noteId, 'Nota');
      own.note_id = a.noteId;
    }
    if (a.status !== undefined) {
      own.status = a.status;
      // Mesma regra de TaskItem.moved do app.
      own.completed_at = a.status === 'done' ? (cur.status === 'done' ? cur.completed_at : ctx.now().toISOString()) : null;
    }
    const newDue = wide && typeof a.dueAt === 'string' ? parseDue(a.dueAt) : null;
    if (Object.keys(shared).length + Object.keys(own).length === 0 && !newDue) {
      throw new UserError('Nada para alterar: informe ao menos um campo.');
    }

    if (!wide) {
      const patch = { ...shared, ...own };
      // A ocorrência editada sai da série (como no app); só status e nota mantêm.
      if (cur.series_id && Object.keys(shared).length > 0) { patch.series_id = null; patch.recurrence = null; }
      const rows = check(await ctx.db.from('tasks').update(patch).eq('id', a.id).eq('user_id', ctx.userId).select('*')) as Row[];
      if (rows.length === 0) throw new UserError('Tarefa não encontrada.');
      return ok({ task: taskOut(rows[0], tz), updated: 1 });
    }

    // `following`/`all` numa série: lê as ocorrências afetadas e regrava de uma vez.
    let q = ctx.db.from('tasks').select('*').eq('user_id', ctx.userId).eq('series_id', cur.series_id).order('due_at', { ascending: true });
    if (scope === 'following') q = q.gte('due_at', cur.due_at);
    const affected = check(await q.limit(1000)) as Row[];
    let seriesId: string = cur.series_id;
    if (scope === 'following') {
      const earlier = check(await ctx.db.from('tasks').select('id').eq('user_id', ctx.userId).eq('series_id', cur.series_id)
        .lt('due_at', cur.due_at).limit(1)) as Row[];
      if (earlier.length > 0) seriesId = randomUUID(); // as seguintes deixam de acompanhar as anteriores
    }
    let dayShift = 0;
    let time: string | null = null;
    if (newDue) {
      const was = localParts(new Date(cur.due_at), tz);
      const now = localParts(newDue, tz);
      dayShift = dayNumber(now.date) - dayNumber(was.date);
      time = now.time;
    }
    const out = affected.map((r) => {
      const row: Row = { ...r, ...shared, series_id: seriesId };
      if (time !== null) {
        const p = localParts(new Date(r.due_at), tz);
        row.due_at = parseWhen(`${addDays(p.date, dayShift)}T${time}:00`, tz).toISOString();
      }
      if (r.id === a.id) Object.assign(row, own);
      return row;
    });
    const saved = check(await ctx.db.from('tasks').upsert(out, { onConflict: 'id' }).select('*')) as Row[];
    const target = saved.find((r) => r.id === a.id);
    if (!target) throw new UserError('Tarefa não encontrada.');
    return ok({ task: taskOut(target, tz), updated: saved.length });
  }));

  server.registerTool('delete_task', {
    title: 'Apagar tarefa',
    description:
      'Apaga uma tarefa pelo id. Irreversível; confirme com o usuário. ' +
      'Em tarefas de série, `scope` escolhe o que apagar: `one` (padrão, só esta), `following` (esta e as seguintes) ' +
      'ou `all` (todas as ocorrências da série, inclusive as concluídas). Em tarefa fora de série, `scope` não muda nada.',
    inputSchema: { id: z.string().uuid(), scope: scopeSchema },
    annotations: DESTRUCTIVE,
  }, safe(async (a) => {
    const scope = a.scope ?? 'one';
    const cur = check(await ctx.db.from('tasks').select('id, series_id, due_at').eq('id', a.id).eq('user_id', ctx.userId).maybeSingle()) as Row | null;
    if (!cur) throw new UserError('Tarefa não encontrada.');
    let del = ctx.db.from('tasks').delete().eq('user_id', ctx.userId);
    if (scope !== 'one' && cur.series_id) {
      // Por series_id (e due_at), não por uma lista de ids: séries longas estouram o tamanho da URL.
      del = del.eq('series_id', cur.series_id);
      if (scope === 'following') del = del.gte('due_at', cur.due_at);
    } else {
      del = del.eq('id', a.id);
    }
    const rows = check(await del.select('id')) as Row[];
    if (rows.length === 0) throw new UserError('Tarefa não encontrada.');
    return ok({ deleted: a.id, deletedCount: rows.length, scope });
  }));
}
