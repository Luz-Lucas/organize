import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { call, connectTools, createTestUser, deleteTestUser, hasDb, serviceClient, type Connected } from './helpers.js';

describe.skipIf(!hasDb)('tarefas recorrentes (Supabase local)', () => {
  let db: SupabaseClient;
  let userA = '';
  let userB = '';
  let a: Connected;
  const fixedNow = new Date('2026-10-19T15:00:00Z'); // seg 12:00 em São Paulo

  beforeAll(async () => {
    db = serviceClient();
    userA = await createTestUser(db, 'ts-a');
    userB = await createTestUser(db, 'ts-b');
    a = await connectTools(db, userA, { now: () => fixedNow });
  });

  afterAll(async () => {
    await a?.close();
    if (userA) await deleteTestUser(db, userA);
    if (userB) await deleteTestUser(db, userB);
  });

  /** Linhas da série, em ordem de prazo. */
  const rows = async (title: string) =>
    (await db.from('tasks').select('*').eq('user_id', userA).eq('title', title).order('due_at')).data as any[];
  const day = (r: any) => (r.due_at as string).slice(0, 10);
  const listed = async (title: string, args: Record<string, unknown> = {}) =>
    ((await call(a.client, 'list_tasks', { limit: 200, ...args })).data.tasks as any[]).filter((t) => t.title === title);
  const mkWeekly = async (title: string, extra: Record<string, unknown> = {}) => {
    const r = await call(a.client, 'create_task', {
      title, dueAt: '2026-10-20T10:00:00', repeat: { freq: 'weekly', until: '2026-12-01' }, ...extra,
    });
    expect(r.isError, r.text).toBe(false);
    return r.data;
  };

  describe('create_task com repeat', () => {
    it('semanal na terça até 1/12 cria 7 ocorrências com o mesmo seriesId e a regra guardada', async () => {
      const r = await mkWeekly('ts-lab');
      expect(r.occurrences).toBe(7);
      expect(r.task.seriesId).toBe(r.seriesId);
      expect(r.task.dueAt).toBe('2026-10-20T10:00:00-03:00');
      expect(r.lastDueAt).toBe('2026-12-01T10:00:00-03:00');
      const rs = await rows('ts-lab');
      expect(rs.map(day)).toEqual(['2026-10-20', '2026-10-27', '2026-11-03', '2026-11-10', '2026-11-17', '2026-11-24', '2026-12-01']);
      expect(new Set(rs.map((x) => x.series_id))).toEqual(new Set([r.seriesId]));
      expect(rs.every((x) => x.status === 'todo' && x.priority === 'media' && x.completed_at === null)).toBe(true);
      expect(rs[0].recurrence).toEqual({ freq: 'weekly', days: [], until: '2026-12-01', count: null });
    });

    it('só data vale até 23:59; prioridade, espaço e descrição vão para todas; o status só na primeira', async () => {
      const sp = (await db.from('spaces').insert({ user_id: userA, name: 'ts-esp' }).select('id').single()).data!.id as string;
      const r = await call(a.client, 'create_task', {
        title: 'ts-extras', description: 'detalhe', priority: 'alta', spaceId: sp, status: 'doing',
        dueAt: '2026-11-02', repeat: { freq: 'daily', count: 3 },
      });
      expect(r.isError, r.text).toBe(false);
      const rs = await rows('ts-extras');
      expect(rs.map((x) => x.status)).toEqual(['doing', 'todo', 'todo']);
      expect(rs.every((x) => x.priority === 'alta' && x.space_id === sp && x.description === 'detalhe')).toBe(true);
      expect(rs[0].due_at).toBe('2026-11-03T02:59:00+00:00');
    });

    it('sem until nem count repete por 3 meses', async () => {
      const r = await call(a.client, 'create_task', { title: 'ts-padrao', dueAt: '2027-02-01T08:00:00', repeat: { freq: 'monthly' } });
      expect(r.data.occurrences).toBe(4);
    });

    it('exige prazo, recusa until antes do prazo e série já concluída', async () => {
      const sem = await call(a.client, 'create_task', { title: 'ts-x', repeat: { freq: 'daily', count: 2 } });
      expect(sem.isError).toBe(true);
      expect(sem.text).toMatch(/prazo/i);
      const ate = await call(a.client, 'create_task', { title: 'ts-x', dueAt: '2027-02-01', repeat: { freq: 'daily', until: '2027-01-01' } });
      expect(ate.isError).toBe(true);
      expect(ate.text).toMatch(/data final/i);
      const done = await call(a.client, 'create_task', { title: 'ts-x', dueAt: '2027-02-01', status: 'done', repeat: { freq: 'daily', count: 2 } });
      expect(done.isError).toBe(true);
      expect((await rows('ts-x'))).toHaveLength(0);
    });

    it('prazo no passado não quebra', async () => {
      const r = await call(a.client, 'create_task', { title: 'ts-passado', dueAt: '2026-01-06', repeat: { freq: 'weekly', count: 2 } });
      expect(r.isError, r.text).toBe(false);
      expect(r.data.occurrences).toBe(2);
    });

    it('sem repeat a tarefa não tem série', async () => {
      const r = await call(a.client, 'create_task', { title: 'ts-solta', dueAt: '2026-11-01' });
      expect(r.data.task.seriesId).toBeNull();
      expect(r.data.task.recurrence).toBeNull();
    });
  });

  describe('list_tasks mostra só a próxima pendente da série', () => {
    it('sem status: uma por série; a atrasada aparece até ser concluída, depois a seguinte', async () => {
      await mkWeekly('ts-lista'); // 20/10 está depois de "agora"; para ter atraso, usa-se série no passado
      expect((await listed('ts-lista')).map((t) => t.dueAt.slice(0, 10))).toEqual(['2026-10-20']);

      await call(a.client, 'create_task', { title: 'ts-atraso', dueAt: '2026-10-06T10:00:00', repeat: { freq: 'weekly', count: 4 } }); // 6/10, 13/10, 20/10, 27/10
      const rs = await rows('ts-atraso');
      expect((await listed('ts-atraso')).map((t) => t.dueAt.slice(0, 10))).toEqual(['2026-10-06']);
      await call(a.client, 'update_task', { id: rs[0].id, status: 'done' });
      expect((await listed('ts-atraso')).map((t) => t.dueAt.slice(0, 10))).toEqual(['2026-10-13']);
      // concluir a mais nova não mexe na próxima; desmarcar a mais antiga a traz de volta
      await call(a.client, 'update_task', { id: rs[2].id, status: 'done' });
      expect((await listed('ts-atraso')).map((t) => t.dueAt.slice(0, 10))).toEqual(['2026-10-13']);
      await call(a.client, 'update_task', { id: rs[0].id, status: 'todo' });
      expect((await listed('ts-atraso')).map((t) => t.dueAt.slice(0, 10))).toEqual(['2026-10-06']);
    });

    it('em andamento conta como pendente; série toda concluída some de pendentes e aparece em done', async () => {
      await call(a.client, 'create_task', { title: 'ts-fim', dueAt: '2026-11-02', repeat: { freq: 'daily', count: 3 } });
      const rs = await rows('ts-fim');
      await call(a.client, 'update_task', { id: rs[1].id, status: 'doing' });
      expect((await listed('ts-fim')).map((t) => [t.dueAt.slice(0, 10), t.status])).toEqual([['2026-11-02', 'todo']]);
      for (const r of rs) await call(a.client, 'update_task', { id: r.id, status: 'done' });
      expect(await listed('ts-fim')).toEqual([]);
      const done = await listed('ts-fim', { status: 'done' });
      expect(done).toHaveLength(3);
    });

    it('com status explícito lista todas as ocorrências daquele status', async () => {
      const todo = await listed('ts-lista', { status: 'todo' });
      expect(todo).toHaveLength(7);
    });

    it('filtros continuam valendo e tarefas avulsas não são afetadas', async () => {
      await call(a.client, 'create_task', { title: 'ts-avulsa', dueAt: '2026-10-21' });
      expect(await listed('ts-avulsa')).toHaveLength(1);
      expect(await listed('ts-lista', { dueBefore: '2026-10-19' })).toEqual([]);
      expect(await listed('ts-lista', { priority: 'alta' })).toEqual([]);
      expect(await listed('ts-lista', { dueBefore: '2026-12-31' })).toHaveLength(1);
    });

    it('seriesId e recurrence saem na listagem', async () => {
      const [t] = await listed('ts-lista');
      expect(t.seriesId).toBeTruthy();
      expect(t.recurrence).toMatchObject({ freq: 'weekly', until: '2026-12-01' });
    });
  });

  describe('update_task com scope', () => {
    it('padrão (one): editar o título tira só essa da série; só o status mantém na série', async () => {
      const { seriesId } = await mkWeekly('ts-one');
      const rs = await rows('ts-one');
      const st = await call(a.client, 'update_task', { id: rs[1].id, status: 'done' });
      expect(st.data.task.seriesId).toBe(seriesId);
      const ed = await call(a.client, 'update_task', { id: rs[2].id, priority: 'alta' });
      expect(ed.isError, ed.text).toBe(false);
      expect(ed.data.task.seriesId).toBeNull();
      expect(ed.data.task.recurrence).toBeNull();
      const now = await rows('ts-one');
      expect(now.filter((x) => x.series_id === seriesId)).toHaveLength(6);
      expect(now.find((x) => x.id === rs[0].id).priority).toBe('media');
    });

    it('all: título/prioridade/descrição/espaço valem para todas; status só para a escolhida', async () => {
      const { seriesId } = await mkWeekly('ts-all');
      const rs = await rows('ts-all');
      const u = await call(a.client, 'update_task', {
        id: rs[3].id, scope: 'all', title: 'ts-all-novo', priority: 'baixa', description: 'nova', status: 'done',
      });
      expect(u.isError, u.text).toBe(false);
      expect(u.data.updated).toBe(7);
      const now = await rows('ts-all-novo');
      expect(now).toHaveLength(7);
      expect(now.every((x) => x.priority === 'baixa' && x.description === 'nova' && x.series_id === seriesId)).toBe(true);
      expect(now.map((x) => x.status)).toEqual(['todo', 'todo', 'todo', 'done', 'todo', 'todo', 'todo']);
      expect(now[3].completed_at).not.toBeNull();
      expect(now.filter((x) => x.completed_at).length).toBe(1);
    });

    it('all com novo prazo desloca o dia e a hora de todas, mantendo o status', async () => {
      await mkWeekly('ts-shift');
      const rs = await rows('ts-shift');
      await call(a.client, 'update_task', { id: rs[1].id, status: 'done' });
      // 27/10 10:00 -> 28/10 15:30 : +1 dia e nova hora em todas
      const u = await call(a.client, 'update_task', { id: rs[1].id, scope: 'all', dueAt: '2026-10-28T15:30:00' });
      expect(u.isError, u.text).toBe(false);
      const now = await rows('ts-shift');
      expect(now.map((x) => x.due_at.slice(0, 16))).toEqual(
        ['2026-10-21', '2026-10-28', '2026-11-04', '2026-11-11', '2026-11-18', '2026-11-25', '2026-12-02'].map((d) => `${d}T18:30`));
      expect(now.map((x) => x.status)).toEqual(['todo', 'done', 'todo', 'todo', 'todo', 'todo', 'todo']);
      expect(new Set(now.map((x) => x.series_id)).size).toBe(1);
    });

    it('following no meio: as seguintes vão para uma série nova, as anteriores ficam', async () => {
      const { seriesId } = await mkWeekly('ts-fol');
      const rs = await rows('ts-fol');
      const u = await call(a.client, 'update_task', { id: rs[3].id, scope: 'following', title: 'ts-fol-novo' });
      expect(u.isError, u.text).toBe(false);
      expect(u.data.updated).toBe(4);
      const antes = await rows('ts-fol');
      const depois = await rows('ts-fol-novo');
      expect(antes).toHaveLength(3);
      expect(depois).toHaveLength(4);
      expect(antes.every((x) => x.series_id === seriesId)).toBe(true);
      const novo = new Set(depois.map((x) => x.series_id));
      expect(novo.size).toBe(1);
      expect(novo.has(seriesId)).toBe(false);
      expect(u.data.task.seriesId).toBe([...novo][0]);
    });

    it('following a partir da primeira não cria série nova', async () => {
      const { seriesId } = await mkWeekly('ts-fol1');
      const rs = await rows('ts-fol1');
      const u = await call(a.client, 'update_task', { id: rs[0].id, scope: 'following', priority: 'alta' });
      expect(u.data.updated).toBe(7);
      const now = await rows('ts-fol1');
      expect(now.every((x) => x.series_id === seriesId && x.priority === 'alta')).toBe(true);
    });

    it('following com prazo novo desloca só as seguintes', async () => {
      await mkWeekly('ts-folshift');
      const rs = await rows('ts-folshift');
      await call(a.client, 'update_task', { id: rs[4].id, scope: 'following', dueAt: '2026-11-19T10:00:00' }); // 17/11 -> 19/11
      const now = await rows('ts-folshift');
      expect(now.map(day)).toEqual(['2026-10-20', '2026-10-27', '2026-11-03', '2026-11-10', '2026-11-19', '2026-11-26', '2026-12-03']);
    });

    it('scope all/following recusa dueAt nulo; fora de série o scope não muda nada', async () => {
      await mkWeekly('ts-nulo');
      const rs = await rows('ts-nulo');
      const bad = await call(a.client, 'update_task', { id: rs[0].id, scope: 'all', dueAt: null });
      expect(bad.isError).toBe(true);
      expect(bad.text).toMatch(/prazo/i);
      const solo = (await call(a.client, 'create_task', { title: 'ts-solo-scope', dueAt: '2026-11-01' })).data.task;
      const u = await call(a.client, 'update_task', { id: solo.id, scope: 'all', title: 'ts-solo-scope2' });
      expect(u.isError, u.text).toBe(false);
      expect(u.data.updated).toBe(1);
      expect(u.data.task.title).toBe('ts-solo-scope2');
    });

    it('não mexe nas tarefas de outro usuário nem em ids inexistentes', async () => {
      const sid = randomUUID();
      const ins = await db.from('tasks').insert([
        { user_id: userB, title: 'ts-alheia', series_id: sid, due_at: '2026-11-01T12:00:00Z' },
        { user_id: userB, title: 'ts-alheia', series_id: sid, due_at: '2026-11-08T12:00:00Z' },
      ]).select('id');
      const r = await call(a.client, 'update_task', { id: ins.data![0].id, scope: 'all', title: 'invadida' });
      expect(r.isError).toBe(true);
      const d = await call(a.client, 'delete_task', { id: ins.data![0].id, scope: 'all' });
      expect(d.isError).toBe(true);
      expect((await db.from('tasks').select('title').eq('series_id', sid)).data!.map((x) => x.title)).toEqual(['ts-alheia', 'ts-alheia']);
    });

    it('séries grandes: all (título) e following (com deslocamento) funcionam com centenas de linhas', async () => {
      const seriesId = randomUUID();
      const base = Date.UTC(2028, 0, 1, 13, 0, 0);
      const data = Array.from({ length: 400 }, (_, i) => ({
        user_id: userA, title: 'ts-enorme', series_id: seriesId, source: 'manual', due_at: new Date(base + i * 86_400_000).toISOString(),
      }));
      for (let i = 0; i < data.length; i += 200) expect((await db.from('tasks').insert(data.slice(i, i + 200))).error).toBeNull();
      const pick = async (idx: number) =>
        (await db.from('tasks').select('id').eq('series_id', seriesId).order('due_at').range(idx, idx)).data![0].id as string;
      const t = await call(a.client, 'update_task', { id: await pick(10), scope: 'all', title: 'ts-enorme2' });
      expect(t.isError, t.text).toBe(false);
      expect(t.data.updated).toBe(400);
      const s = await call(a.client, 'update_task', { id: await pick(100), scope: 'following', dueAt: '2028-04-12T10:00:00' }); // 11/04 10:00 -> 12/04 10:00
      expect(s.isError, s.text).toBe(false);
      expect(s.data.updated).toBe(300);
      const first = (await db.from('tasks').select('due_at').eq('title', 'ts-enorme2').order('due_at').limit(1)).data![0];
      expect(first.due_at.slice(0, 10)).toBe('2028-01-01');
      // o following a partir da 101ª criou uma série nova com as outras 300
      const del = await call(a.client, 'delete_task', { id: await pick(0), scope: 'all' });
      expect(del.data.deletedCount).toBe(100);
      const rest = (await db.from('tasks').select('id').eq('user_id', userA).eq('title', 'ts-enorme2')).data!;
      expect(rest).toHaveLength(300);
      expect((await call(a.client, 'delete_task', { id: rest[0].id, scope: 'all' })).data.deletedCount).toBe(300);
    });
  });

  describe('delete_task com scope', () => {
    const mk = async (title: string) => {
      await call(a.client, 'create_task', { title, dueAt: '2026-11-02T10:00:00', repeat: { freq: 'daily', count: 5 } });
      return rows(title);
    };

    it('padrão apaga só uma; following apaga esta e as seguintes; all apaga a série', async () => {
      const rs = await mk('ts-del');
      const one = await call(a.client, 'delete_task', { id: rs[2].id });
      expect(one.data).toMatchObject({ deletedCount: 1, scope: 'one' });
      expect(await rows('ts-del')).toHaveLength(4);

      const left = await rows('ts-del');
      const fol = await call(a.client, 'delete_task', { id: left[2].id, scope: 'following' });
      expect(fol.data.deletedCount).toBe(2);
      expect((await rows('ts-del')).map(day)).toEqual(['2026-11-02', '2026-11-03']);

      const all = await call(a.client, 'delete_task', { id: (await rows('ts-del'))[1].id, scope: 'all' });
      expect(all.data.deletedCount).toBe(2);
      expect(await rows('ts-del')).toHaveLength(0);
    });

    it('all apaga também as concluídas; fora de série apaga só a própria', async () => {
      const rs = await mk('ts-del2');
      await call(a.client, 'update_task', { id: rs[0].id, status: 'done' });
      const all = await call(a.client, 'delete_task', { id: rs[4].id, scope: 'all' });
      expect(all.data.deletedCount).toBe(5);
      const solo = (await call(a.client, 'create_task', { title: 'ts-del-solo' })).data.task;
      const d = await call(a.client, 'delete_task', { id: solo.id, scope: 'all' });
      expect(d.data.deletedCount).toBe(1);
      expect((await call(a.client, 'delete_task', { id: solo.id })).isError).toBe(true);
    });
  });
});
