import { z } from 'zod';
import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import type { ToolContext } from './index.js';
import { READ, UserError, WRITE, addDaysYmd, assertOwned, check, fold, localYmd, ok, okData, safe, toIso } from './util.js';

type Row = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any

const num = (v: unknown): number | null => (v === null || v === undefined ? null : Number(v));

export function exerciseOut(r: Row) {
  return {
    id: r.id, name: r.name, sets: r.sets, reps: r.reps, loadKg: num(r.load_kg),
    restSeconds: r.rest_seconds, notes: r.notes, position: r.position,
  };
}

const exerciseIn = z.object({
  id: z.string().uuid().optional().describe('id de um exercício já existente desta ficha (mantém o histórico dele)'),
  name: z.string().trim().min(1).max(80),
  sets: z.number().int().min(1).max(20).optional().describe('Séries (padrão 3)'),
  reps: z.string().trim().min(1).max(20).optional().describe('Repetições como texto, ex.: "8-12" (padrão "10")'),
  loadKg: z.number().min(0).max(9999).nullable().optional().describe('Carga planejada em kg'),
  restSeconds: z.number().int().min(0).max(900).optional().describe('Descanso em segundos (padrão 90)'),
  notes: z.string().max(500).optional(),
});

async function workoutOut(ctx: ToolContext, w: Row) {
  const ex = check(await ctx.db.from('workout_exercises').select('*')
    .eq('user_id', ctx.userId).eq('workout_id', w.id).order('position')) as Row[];
  return { id: w.id, name: w.name, position: w.position, exercises: ex.map(exerciseOut) };
}

export function registerFitness(server: McpServer, ctx: ToolContext): void {
  const tz = ctx.timeZone;

  server.registerTool('list_workouts', {
    title: 'Listar fichas de treino',
    description: 'Lista as fichas de treino (Treino A, B…) na ordem do rodízio, cada uma com seus exercícios.',
    inputSchema: {},
    annotations: READ,
  }, safe(async () => {
    const ws = check(await ctx.db.from('workouts').select('*').eq('user_id', ctx.userId).order('position').order('created_at')) as Row[];
    const ex = ws.length === 0 ? [] : check(await ctx.db.from('workout_exercises').select('*')
      .eq('user_id', ctx.userId).in('workout_id', ws.map((w) => w.id)).order('position')) as Row[];
    return okData({
      workouts: ws.map((w) => ({
        id: w.id, name: w.name, position: w.position,
        exercises: ex.filter((e) => e.workout_id === w.id).map(exerciseOut),
      })),
    });
  }));

  server.registerTool('upsert_workout', {
    title: 'Criar ou editar ficha de treino',
    description:
      'Cria uma ficha (sem `id`) ou edita a existente (com `id`). `exercises` SUBSTITUI a lista inteira, na ordem dada: ' +
      'exercícios que saem são apagados; quem continua (mesmo `id` ou mesmo nome) mantém o id e o histórico. ' +
      'Campos omitidos voltam ao padrão (3 séries, "10" repetições, 90 s, sem carga).',
    inputSchema: {
      id: z.string().uuid().optional(), name: z.string().trim().min(1).max(60),
      exercises: z.array(exerciseIn).max(60),
    },
    annotations: { ...WRITE, idempotentHint: true },
  }, safe(async (a) => {
    let workout: Row;
    if (a.id) {
      await assertOwned(ctx, 'workouts', a.id, 'Ficha');
      const rows = check(await ctx.db.from('workouts').update({ name: a.name })
        .eq('id', a.id).eq('user_id', ctx.userId).select('*')) as Row[];
      if (rows.length === 0) throw new UserError('Ficha não encontrada.');
      workout = rows[0];
    } else {
      const all = check(await ctx.db.from('workouts').select('position').eq('user_id', ctx.userId)) as Row[];
      const next = all.reduce((m, r) => Math.max(m, Number(r.position) + 1), 0);
      workout = check(await ctx.db.from('workouts').insert({ user_id: ctx.userId, name: a.name, position: next }).select('*').single()) as Row;
    }

    const existing = a.id
      ? check(await ctx.db.from('workout_exercises').select('*').eq('user_id', ctx.userId).eq('workout_id', workout.id)) as Row[]
      : [];
    // Casa primeiro por id, depois por nome (sem acento/caixa); exercício de outra ficha nunca casa.
    const used = new Set<string>();
    const matchOf: Array<Row | null> = a.exercises.map(() => null);
    a.exercises.forEach((e, i) => {
      const hit = e.id ? existing.find((x) => x.id === e.id && !used.has(x.id)) : undefined;
      if (hit) { used.add(hit.id); matchOf[i] = hit; }
    });
    a.exercises.forEach((e, i) => {
      if (matchOf[i]) return;
      const hit = existing.find((x) => !used.has(x.id) && fold(x.name) === fold(e.name));
      if (hit) { used.add(hit.id); matchOf[i] = hit; }
    });

    const fields = (e: z.infer<typeof exerciseIn>, position: number) => ({
      name: e.name, sets: e.sets ?? 3, reps: e.reps ?? '10', load_kg: e.loadKg ?? null,
      rest_seconds: e.restSeconds ?? 90, notes: e.notes ?? '', position,
    });
    const created: Row[] = [];
    for (let i = 0; i < a.exercises.length; i++) {
      const m = matchOf[i];
      if (m) {
        check(await ctx.db.from('workout_exercises').update(fields(a.exercises[i], i)).eq('id', m.id).eq('user_id', ctx.userId));
      } else {
        created.push({ user_id: ctx.userId, workout_id: workout.id, ...fields(a.exercises[i], i) });
      }
    }
    if (created.length) check(await ctx.db.from('workout_exercises').insert(created));
    const gone = existing.filter((x) => !used.has(x.id)).map((x) => x.id);
    if (gone.length) check(await ctx.db.from('workout_exercises').delete().eq('user_id', ctx.userId).in('id', gone));

    return ok({ workout: await workoutOut(ctx, workout) });
  }));

  server.registerTool('list_workout_history', {
    title: 'Histórico de treinos',
    description:
      'Sessões de treino dos últimos `days` dias (padrão 30), da mais recente para a mais antiga, cada uma com as séries ' +
      'feitas (exercício, número da série, repetições, carga em kg). `finishedAt` nulo = treino ainda em andamento.',
    inputSchema: { days: z.number().int().min(1).max(365).optional() },
    annotations: READ,
  }, safe(async (a) => {
    const from = addDaysYmd(localYmd(ctx.now(), tz), -(a.days ?? 30));
    const sessions = check(await ctx.db.from('workout_sessions').select('*')
      .eq('user_id', ctx.userId).gte('day', from).order('day', { ascending: false })
      .order('started_at', { ascending: false }).limit(200)) as Row[];
    const logs = sessions.length === 0 ? [] : check(await ctx.db.from('set_logs').select('*')
      .eq('user_id', ctx.userId).in('session_id', sessions.map((s) => s.id)).order('done_at')) as Row[];
    return okData({
      sessions: sessions.map((s) => ({
        id: s.id, workoutId: s.workout_id, workoutName: s.workout_name, day: s.day,
        startedAt: toIso(s.started_at, tz), finishedAt: toIso(s.finished_at, tz),
        sets: logs.filter((l) => l.session_id === s.id).sort((x, y) => String(x.exercise_name).localeCompare(String(y.exercise_name)) || x.set_index - y.set_index)
          .map((l) => ({ exerciseName: l.exercise_name, setIndex: l.set_index, reps: l.reps, loadKg: num(l.load_kg), doneAt: toIso(l.done_at, tz) })),
      })),
    });
  }));
}
