import { z } from 'zod';
import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import type { ToolContext } from './index.js';
import {
  DESTRUCTIVE, READ, UserError, WRITE, assertOwned, check, clampLimit, ok, okData, parseWhen, safe, toIso,
} from './util.js';

type Row = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any

const title = z.string().trim().min(1).max(200);
const status = z.enum(['todo', 'doing', 'done']);
const priority = z.enum(['baixa', 'media', 'alta']);
const when = z.string().min(8).max(40);

export function taskOut(r: Row, tz: string) {
  return {
    id: r.id, title: r.title, description: r.description, status: r.status, priority: r.priority,
    dueAt: toIso(r.due_at, tz), completedAt: toIso(r.completed_at, tz), spaceId: r.space_id, noteId: r.note_id,
  };
}

const RANK: Record<string, number> = { doing: 0, todo: 1, done: 2 };

export function registerTasks(server: McpServer, ctx: ToolContext): void {
  const tz = ctx.timeZone;
  const parseDue = (s: string) => parseWhen(s, tz, [23, 59, 0]);

  server.registerTool('list_tasks', {
    title: 'Listar tarefas',
    description:
      'Lista tarefas ordenadas: em andamento, a fazer, depois concluídas; dentro de cada grupo por prazo (sem prazo por último). ' +
      'Sem `status`, as concluídas ficam de fora (peça `status: "done"` para vê-las).',
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
    const rows = check(await q.limit(2000)) as Row[];
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
    description: 'Cria uma tarefa. `dueAt` aceita só data (vale até 23:59 desse dia). `priority`: baixa, media (padrão) ou alta.',
    inputSchema: {
      title, description: z.string().max(10_000).optional(), status: status.optional(), priority: priority.optional(),
      dueAt: when.optional(), spaceId: z.string().uuid().optional(), noteId: z.string().uuid().optional(),
    },
    annotations: { ...WRITE, idempotentHint: false },
  }, safe(async (a) => {
    if (a.spaceId) await assertOwned(ctx, 'spaces', a.spaceId, 'Espaço');
    if (a.noteId) await assertOwned(ctx, 'notes', a.noteId, 'Nota');
    const st = a.status ?? 'todo';
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
      '`dueAt: null` remove o prazo. `priority`: baixa, media ou alta.',
    inputSchema: {
      id: z.string().uuid(), title: title.optional(), description: z.string().max(10_000).optional(),
      status: status.optional(), priority: priority.optional(), dueAt: when.nullable().optional(),
      spaceId: z.string().uuid().nullable().optional(), noteId: z.string().uuid().nullable().optional(),
    },
    annotations: { ...WRITE, idempotentHint: true },
  }, safe(async (a) => {
    const cur = check(await ctx.db.from('tasks').select('*').eq('id', a.id).eq('user_id', ctx.userId).maybeSingle()) as Row | null;
    if (!cur) throw new UserError('Tarefa não encontrada.');
    const patch: Row = {};
    if (a.title !== undefined) patch.title = a.title;
    if (a.description !== undefined) patch.description = a.description;
    if (a.priority !== undefined) patch.priority = a.priority;
    if (a.dueAt !== undefined) patch.due_at = a.dueAt === null ? null : parseDue(a.dueAt).toISOString();
    if (a.spaceId !== undefined) {
      if (a.spaceId) await assertOwned(ctx, 'spaces', a.spaceId, 'Espaço');
      patch.space_id = a.spaceId;
    }
    if (a.noteId !== undefined) {
      if (a.noteId) await assertOwned(ctx, 'notes', a.noteId, 'Nota');
      patch.note_id = a.noteId;
    }
    if (a.status !== undefined) {
      patch.status = a.status;
      // Mesma regra de TaskItem.moved do app.
      patch.completed_at = a.status === 'done' ? (cur.status === 'done' ? cur.completed_at : ctx.now().toISOString()) : null;
    }
    if (Object.keys(patch).length === 0) throw new UserError('Nada para alterar: informe ao menos um campo.');
    const rows = check(await ctx.db.from('tasks').update(patch).eq('id', a.id).eq('user_id', ctx.userId).select('*')) as Row[];
    if (rows.length === 0) throw new UserError('Tarefa não encontrada.');
    return ok({ task: taskOut(rows[0], tz) });
  }));

  server.registerTool('delete_task', {
    title: 'Apagar tarefa',
    description: 'Apaga uma tarefa pelo id. Irreversível; confirme com o usuário.',
    inputSchema: { id: z.string().uuid() },
    annotations: DESTRUCTIVE,
  }, safe(async (a) => {
    const rows = check(await ctx.db.from('tasks').delete().eq('id', a.id).eq('user_id', ctx.userId).select('id')) as Row[];
    if (rows.length === 0) throw new UserError('Tarefa não encontrada.');
    return ok({ deleted: a.id });
  }));
}
