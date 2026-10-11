import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { beforeAll, describe, expect, it } from 'vitest';
import { SupabaseStore } from '../src/supabase-store.js';

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;

describe.skipIf(!url || !key)('SupabaseStore (integração)', () => {
  let db: SupabaseClient;
  let store: SupabaseStore;
  let userId: string;

  beforeAll(async () => {
    db = createClient(url!, key!, { auth: { persistSession: false } });
    const { data, error } = await db.auth.admin.createUser({
      email: `ponte-${Date.now()}@local.test`, password: 'senha-de-teste-123', email_confirm: true,
    });
    if (error) throw error;
    userId = data.user.id;
    store = new SupabaseStore(db, userId, () => {});
  });

  const newPlan = async () => {
    const { data, error } = await db.from('wake_plans')
      .insert({ user_id: userId, label: 'Teste', days: [1, 2, 3, 4, 5, 6, 7], time: '07:00', echo_device_id: 'ECHO' })
      .select().single();
    if (error) throw error;
    return data.id as string;
  };

  it('reivindica o despertar uma única vez', async () => {
    const planId = await newPlan();
    const at = new Date('2026-09-28T10:00:00Z');
    expect(await store.claimRun(planId, '2026-09-28', at)).toBe(true);
    expect(await store.claimRun(planId, '2026-09-28', at)).toBe(false);
  });

  it('run armado pode ser reivindicado; concluído não', async () => {
    const planId = await newPlan();
    const at = new Date('2026-09-29T10:00:00Z');
    await store.armRun(planId, '2026-09-29', at, 'reserva');
    expect((await store.listWakeRuns('2026-09-29')).find((r) => r.planId === planId)?.fallbackHandle).toBe('reserva');
    expect(await store.claimRun(planId, '2026-09-29', at)).toBe(true);
    await store.finishRun(planId, '2026-09-29', 'done', '');
    expect(await store.claimRun(planId, '2026-09-29', at)).toBe(false);
  });

  it('comando é reivindicado uma vez e sai da fila', async () => {
    const { data } = await db.from('alexa_commands')
      .insert({ user_id: userId, kind: 'speak', payload: { text: 'oi' } }).select().single();
    expect((await store.pendingCommands()).map((c) => c.id)).toContain(data!.id);
    expect(await store.claimCommand(data!.id)).toBe(true);
    expect(await store.claimCommand(data!.id)).toBe(false);
    await store.finishCommand(data!.id, 'done', 'ok');
    expect((await store.pendingCommands()).map((c) => c.id)).not.toContain(data!.id);
  });

  it('briefingInput respeita o dia local de São Paulo', async () => {
    await db.from('events').insert([
      { user_id: userId, title: 'Manhã', starts_at: '2026-09-28T11:00:00Z', ends_at: '2026-09-28T12:00:00Z' },
      { user_id: userId, title: 'Noite', starts_at: '2026-09-29T02:30:00Z', ends_at: '2026-09-29T02:50:00Z' },
      { user_id: userId, title: 'Amanhã', starts_at: '2026-09-29T03:30:00Z', ends_at: '2026-09-29T04:00:00Z' },
    ]);
    await db.from('tasks').insert([
      { user_id: userId, title: 'Atrasada', status: 'todo', due_at: '2026-09-27T20:00:00Z' },
      { user_id: userId, title: 'Hoje', status: 'todo', due_at: '2026-09-28T20:00:00Z' },
      { user_id: userId, title: 'Feita', due_at: '2026-09-28T20:00:00Z', status: 'done' },
    ]);
    const input = await store.briefingInput(new Date('2026-09-28T13:00:00Z'), 'America/Sao_Paulo');
    expect(input.events.map((e) => e.title)).toEqual(['Manhã', 'Noite']);
    expect(input.overdue.map((t) => t.title)).toEqual(['Atrasada']);
    expect(input.dueToday.map((t) => t.title)).toEqual(['Hoje']);
  });

  it('briefingInput inclui evento de duração zero à meia-noite local e exclui o que termina nela', async () => {
    const other = await db.auth.admin.createUser({
      email: `ponte-meia-noite-${Date.now()}@local.test`, password: 'senha-de-teste-123', email_confirm: true,
    });
    if (other.error) throw other.error;
    const uid = other.data.user.id;
    const s = new SupabaseStore(db, uid, () => {});
    await db.from('events').insert([
      { user_id: uid, title: 'Zero à meia-noite', starts_at: '2026-10-05T03:00:00Z', ends_at: '2026-10-05T03:00:00Z' },
      { user_id: uid, title: 'Terminou à meia-noite', starts_at: '2026-10-05T02:00:00Z', ends_at: '2026-10-05T03:00:00Z' },
    ]);
    const input = await s.briefingInput(new Date('2026-10-05T13:00:00Z'), 'America/Sao_Paulo');
    expect(input.events.map((e) => e.title)).toEqual(['Zero à meia-noite']);
  });

  it('sweepStuckCommands marca como falhos os comandos presos em execução', async () => {
    const old = new Date(Date.now() - 20 * 60_000).toISOString();
    const { data } = await db.from('alexa_commands')
      .insert({ user_id: userId, kind: 'sync', status: 'running', started_at: old }).select().single();
    const { data: fresh } = await db.from('alexa_commands')
      .insert({ user_id: userId, kind: 'sync', status: 'running', started_at: new Date().toISOString() }).select().single();
    expect(await store.sweepStuckCommands()).toBe(1);
    const rows = (await db.from('alexa_commands').select('id, status').in('id', [data!.id, fresh!.id])).data!;
    expect(rows.find((r) => r.id === data!.id)?.status).toBe('failed');
    expect(rows.find((r) => r.id === fresh!.id)?.status).toBe('running');
  });

  it('comando de outro usuário não pode ser reivindicado nem finalizado', async () => {
    const other = await db.auth.admin.createUser({
      email: `ponte-outro-${Date.now()}@local.test`, password: 'senha-de-teste-123', email_confirm: true,
    });
    if (other.error) throw other.error;
    const { data } = await db.from('alexa_commands')
      .insert({ user_id: other.data.user.id, kind: 'speak', payload: {} }).select().single();
    expect(await store.claimCommand(data!.id)).toBe(false);
    await store.finishCommand(data!.id, 'done', 'invasor');
    const row = (await db.from('alexa_commands').select('status, result').eq('id', data!.id).single()).data!;
    expect(row).toEqual({ status: 'pending', result: null });
  });

  it('saveDevices remove dispositivos que sumiram', async () => {
    await store.saveDevices([{ id: 'E1', name: 'Echo', online: true }], [{ id: 'L1', name: 'Luz', operations: ['turnOn'] }]);
    await store.saveDevices([{ id: 'E1', name: 'Echo', online: false }], []);
    const { data } = await db.from('alexa_devices').select('id, online').eq('user_id', userId);
    expect(data).toEqual([{ id: 'E1', online: false }]);
  });
  it('finishRun aceita skipped; listWakeRuns devolve o status e toPlan lê os campos novos', async () => {
    const planId = await newPlan();
    const at = new Date('2026-10-13T10:00:00Z');
    await store.armRun(planId, '2026-10-13', at, 'reserva');
    expect(await store.claimRun(planId, '2026-10-13', at)).toBe(true);
    await store.finishRun(planId, '2026-10-13', 'skipped', 'fora de casa (a 900 m)');
    const run = (await store.listWakeRuns('2026-10-13')).find((r) => r.planId === planId);
    expect(run?.status).toBe('skipped');
    expect(await store.claimRun(planId, '2026-10-13', at)).toBe(false);
    const plan = (await store.listWakePlans()).find((p) => p.id === planId);
    expect(plan).toMatchObject({ includeWeather: true, deviceActions: [], phoneAlarm: 'fallback', briefingDelaySec: null });
  });

  it('loadPresenceInput filtra pelo usuário: sem dados -> padrões; com dados -> só os dele', async () => {
    const mk = async (tag: string) => {
      const u = await db.auth.admin.createUser({
        email: `ponte-${tag}-${Date.now()}@local.test`, password: 'senha-de-teste-123', email_confirm: true,
      });
      if (u.error) throw u.error;
      return u.data.user.id;
    };
    const a = await mk('pres-a');
    const b = await mk('pres-b');
    const sa = new SupabaseStore(db, a, () => {});
    expect(await sa.loadPresenceInput()).toEqual({ home: null, requireHome: true, location: null });

    const ok = (res: { error: { message: string } | null }) => { if (res.error) throw new Error(res.error.message); };
    ok(await db.from('user_settings').insert([
      { user_id: a, home_lat: -19.9167, home_lon: -45.7, home_radius_m: 80, require_home: false },
      { user_id: b, home_lat: 10, home_lon: 10, home_radius_m: 50, require_home: true },
    ]));
    ok(await db.from('user_locations').insert([
      { user_id: a, lat: -22.2, lon: -45.6, accuracy_m: 12, reported_at: '2026-10-13T10:00:00Z' },
      { user_id: b, lat: 1, lon: 1, accuracy_m: null, reported_at: '2026-10-13T10:00:00Z' },
    ]));
    expect(await sa.loadPresenceInput()).toEqual({
      home: { lat: -19.9167, lon: -45.7, radiusM: 80 }, requireHome: false,
      location: { lat: -22.2, lon: -45.6, accuracyM: 12, reportedAt: new Date('2026-10-13T10:00:00Z') },
    });
  });
});
