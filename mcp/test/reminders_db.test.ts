import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { call, connectTools, createTestUser, deleteTestUser, hasDb, serviceClient, type Connected } from './helpers.js';

describe.skipIf(!hasDb)('lembretes (Supabase local)', () => {
  let db: SupabaseClient;
  let userA = '';
  let a: Connected;
  const fixedNow = new Date('2026-10-19T15:00:00Z');

  beforeAll(async () => {
    db = serviceClient();
    userA = await createTestUser(db, 'rem-a');
    a = await connectTools(db, userA, { now: () => fixedNow });
  });

  afterAll(async () => {
    await a?.close();
    if (userA) await deleteTestUser(db, userA);
  });

  const taskRows = async (title: string) =>
    (await db.from('tasks').select('*').eq('user_id', userA).eq('title', title).order('due_at')).data as any[];
  const eventRows = async (title: string) =>
    (await db.from('events').select('*').eq('user_id', userA).eq('title', title).order('starts_at')).data as any[];

  describe('tarefas', () => {
    it('sem `reminders` usa o padrão {60} e a saída traz o campo', async () => {
      const r = await call(a.client, 'create_task', { title: 'rem-padrao', dueAt: '2026-10-25T18:00:00' });
      expect(r.isError, r.text).toBe(false);
      expect(r.data.task.reminders).toEqual([60]);
      expect((await taskRows('rem-padrao'))[0].reminders).toEqual([60]);
    });

    it('create_task grava os lembretes escolhidos, inclusive nenhum', async () => {
      const r = await call(a.client, 'create_task', { title: 'rem-varios', dueAt: '2026-10-25T18:00:00', reminders: [1440, 15] });
      expect(r.data.task.reminders).toEqual([1440, 15]);
      const n = await call(a.client, 'create_task', { title: 'rem-nenhum', reminders: [] });
      expect(n.data.task.reminders).toEqual([]);
    });

    it('valor repetido vira um só; valor fora das opções é recusado', async () => {
      const r = await call(a.client, 'create_task', { title: 'rem-dup', reminders: [30, 30, 60] });
      expect(r.isError, r.text).toBe(false);
      expect(r.data.task.reminders).toEqual([30, 60]);
      const bad = await call(a.client, 'create_task', { title: 'rem-ruim', reminders: [45] });
      expect(bad.isError).toBe(true);
      expect(await taskRows('rem-ruim')).toHaveLength(0);
    });

    it('update_task troca os lembretes sem tirar a tarefa da série', async () => {
      const c = await call(a.client, 'create_task', { title: 'rem-edit', dueAt: '2026-10-25T18:00:00' });
      const u = await call(a.client, 'update_task', { id: c.data.task.id, reminders: [15] });
      expect(u.isError, u.text).toBe(false);
      expect(u.data.task.reminders).toEqual([15]);
      expect((await taskRows('rem-edit'))[0].reminders).toEqual([15]);
      const bad = await call(a.client, 'update_task', { id: c.data.task.id, reminders: [7] });
      expect(bad.isError).toBe(true);
    });

    it('série: todas as ocorrências nascem com os lembretes; scope all/one em update_task', async () => {
      const c = await call(a.client, 'create_task', {
        title: 'rem-serie', dueAt: '2026-10-20T10:00:00', reminders: [30], repeat: { freq: 'weekly', count: 3 },
      });
      expect(c.isError, c.text).toBe(false);
      expect((await taskRows('rem-serie')).map((r) => r.reminders)).toEqual([[30], [30], [30]]);

      const [first, second] = await taskRows('rem-serie');
      const one = await call(a.client, 'update_task', { id: second.id, reminders: [1440] });
      expect(one.isError, one.text).toBe(false);
      let rs = await taskRows('rem-serie');
      expect(rs.map((r) => r.reminders)).toEqual([[30], [1440], [30]]);
      expect(rs.every((r) => r.series_id === first.series_id)).toBe(true); // só lembretes: continua na série

      const all = await call(a.client, 'update_task', { id: first.id, reminders: [60, 15], scope: 'all' });
      expect(all.isError, all.text).toBe(false);
      expect(all.data.updated).toBe(3);
      rs = await taskRows('rem-serie');
      expect(rs.map((r) => r.reminders)).toEqual([[60, 15], [60, 15], [60, 15]]);
    });

    it('list_tasks traz `reminders`', async () => {
      const r = await call(a.client, 'list_tasks', { limit: 200 });
      const t = (r.data.tasks as any[]).find((x) => x.title === 'rem-varios');
      expect(t.reminders).toEqual([1440, 15]);
    });
  });

  describe('eventos', () => {
    it('sem `reminders` usa o padrão {30} e a saída traz o campo', async () => {
      const r = await call(a.client, 'create_event', { title: 'rem-ev-padrao', startsAt: '2026-10-25T15:00:00' });
      expect(r.isError, r.text).toBe(false);
      expect(r.data.event.reminders).toEqual([30]);
      expect((await eventRows('rem-ev-padrao'))[0].reminders).toEqual([30]);
    });

    it('create_event grava os escolhidos, dedupe e recusa valor inválido', async () => {
      const r = await call(a.client, 'create_event', { title: 'rem-ev-varios', startsAt: '2026-10-25T15:00:00', reminders: [60, 1440, 60] });
      expect(r.data.event.reminders).toEqual([60, 1440]);
      const n = await call(a.client, 'create_event', { title: 'rem-ev-nenhum', startsAt: '2026-10-25T16:00:00', reminders: [] });
      expect(n.data.event.reminders).toEqual([]);
      const bad = await call(a.client, 'create_event', { title: 'rem-ev-ruim', startsAt: '2026-10-25T17:00:00', reminders: [0] });
      expect(bad.isError).toBe(true);
      expect(await eventRows('rem-ev-ruim')).toHaveLength(0);
    });

    it('série de eventos copia os lembretes para todas as ocorrências', async () => {
      const r = await call(a.client, 'create_event', {
        title: 'rem-ev-serie', startsAt: '2026-10-20T08:00:00', reminders: [15], repeat: { freq: 'weekly', count: 3 },
      });
      expect(r.isError, r.text).toBe(false);
      expect((await eventRows('rem-ev-serie')).map((x) => x.reminders)).toEqual([[15], [15], [15]]);
    });

    it('update_event troca só os lembretes sem mexer em horário nem série', async () => {
      const [ev] = await eventRows('rem-ev-padrao');
      const u = await call(a.client, 'update_event', { id: ev.id, reminders: [1440, 15] });
      expect(u.isError, u.text).toBe(false);
      expect(u.data.event.reminders).toEqual([1440, 15]);
      const [after] = await eventRows('rem-ev-padrao');
      expect(after.starts_at).toBe(ev.starts_at);

      const [s] = await eventRows('rem-ev-serie');
      await call(a.client, 'update_event', { id: s.id, reminders: [60] });
      const rs = await eventRows('rem-ev-serie');
      expect(rs.map((x) => x.reminders)).toEqual([[60], [15], [15]]);
      expect(rs.every((x) => x.series_id === s.series_id)).toBe(true);
    });

    it('list_agenda traz `reminders` nos eventos e nas tarefas', async () => {
      const r = await call(a.client, 'list_agenda', { from: '2026-10-25', to: '2026-10-26', includeTasks: true });
      const e = (r.data.events as any[]).find((x) => x.title === 'rem-ev-varios');
      expect(e.reminders).toEqual([60, 1440]);
      const t = (r.data.tasks as any[]).find((x) => x.title === 'rem-varios');
      expect(t.reminders).toEqual([1440, 15]);
    });
  });
});
