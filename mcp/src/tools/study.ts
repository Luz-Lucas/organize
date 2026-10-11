import { z } from 'zod';
import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import type { ToolContext } from './index.js';
import { WRITE, UserError, assertOwned, check, addDaysYmd, ok, parseWhen, safe, toIso } from './util.js';
import { insertNoteUniqueTitle } from './notes.js';

export function registerStudy(server: McpServer, ctx: ToolContext): void {
  const tz = ctx.timeZone;

  server.registerTool('create_study_plan', {
    title: 'Criar plano de estudos',
    description:
      'Cria uma nota com o plano e uma série de tarefas (`weeks` × `sessionsPerWeek` sessões, até 12 semanas e 7 sessões/semana) ' +
      'com prazos crescentes a partir de `startDate`. Os tópicos são distribuídos em rodízio pelas sessões. Retorna os ids.',
    inputSchema: {
      subject: z.string().trim().min(1).max(150),
      startDate: z.string().min(8).max(40).describe('AAAA-MM-DD (primeiro dia do plano)'),
      topics: z.array(z.string().trim().min(1).max(200)).min(1).max(100),
      sessionsPerWeek: z.number().int().min(1).max(7),
      weeks: z.number().int().min(1).max(12),
      spaceId: z.string().uuid().optional(),
    },
    annotations: { ...WRITE, idempotentHint: false },
  }, safe(async (a) => {
    const sessions = a.weeks * a.sessionsPerWeek;
    if (a.topics.length > sessions) {
      throw new UserError(`Há ${a.topics.length} tópicos para só ${sessions} sessões. Aumente as semanas/sessões ou reduza os tópicos.`);
    }
    if (a.spaceId) await assertOwned(ctx, 'spaces', a.spaceId, 'Espaço');
    const start = parseWhen(a.startDate, tz);
    const startYmd = toIso(start, tz)!.slice(0, 10);
    const plan: { n: number; topic: string; due: Date }[] = [];
    for (let i = 0; i < sessions; i++) {
      const week = Math.floor(i / a.sessionsPerWeek);
      const k = i % a.sessionsPerWeek;
      const ymd = addDaysYmd(startYmd, week * 7 + Math.floor((k * 7) / a.sessionsPerWeek));
      plan.push({ n: i + 1, topic: a.topics[i % a.topics.length], due: parseWhen(ymd, tz, [23, 59, 0]) });
    }
    const lines = plan.map((p) => `- Sessão ${p.n} (${toIso(p.due, tz)!.slice(0, 10)}): ${p.topic}`);
    const body = `# Plano de estudos — ${a.subject}\n\nInício: ${startYmd} · ${a.weeks} semana(s) · ${a.sessionsPerWeek} sessão(ões) por semana\n\n${lines.join('\n')}\n`;
    const note = await insertNoteUniqueTitle(ctx, `Plano de estudos — ${a.subject}`, body, a.spaceId);
    const res = await ctx.db.from('tasks').insert(plan.map((p) => ({
      user_id: ctx.userId, title: `${a.subject}: ${p.topic}`.slice(0, 200), description: `Sessão ${p.n} de ${sessions}`,
      status: 'todo', due_at: p.due.toISOString(), space_id: a.spaceId ?? null, note_id: note.id, source: 'manual',
    }))).select('id,title,due_at');
    if (res.error) {
      await ctx.db.from('notes').delete().eq('id', note.id).eq('user_id', ctx.userId);
      check(res);
    }
    return ok({
      note: { id: note.id, title: note.title },
      tasks: (res.data ?? []).map((t) => ({ id: t.id, title: t.title, dueAt: toIso(t.due_at, tz) })),
    });
  }));
}
