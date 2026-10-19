import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { call, connectTools, createTestUser, deleteTestUser, hasDb, serviceClient, type Connected } from './helpers.js';

describe.skipIf(!hasDb)('compras e academia (Supabase local)', () => {
  let db: SupabaseClient;
  let userA = '';
  let userB = '';
  let a: Connected;
  const fixedNow = new Date('2026-10-19T15:00:00Z');

  beforeAll(async () => {
    db = serviceClient();
    userA = await createTestUser(db, 'fs-a');
    userB = await createTestUser(db, 'fs-b');
    a = await connectTools(db, userA, { now: () => fixedNow });
  });

  afterAll(async () => {
    await a?.close();
    if (userA) await deleteTestUser(db, userA);
    if (userB) await deleteTestUser(db, userB);
  });

  it('o gatilho escolhe a seção; seção informada vale; correção é lembrada', async () => {
    const r = await call(a.client, 'add_shopping_items', {
      items: [{ name: 'Leite', quantity: '2 L' }, { name: 'água sanitária' }, { name: 'Pão francês' }, { name: 'Sabão', section: 'higiene' }],
    });
    expect(r.isError).toBe(false);
    const sec = Object.fromEntries(r.data.added.map((i: any) => [i.name, i.section]));
    expect(sec).toEqual({ Leite: 'frios', 'água sanitária': 'limpeza', 'Pão francês': 'padaria', Sabão: 'higiene' });
    // corrigir a seção e recolocar o item: o app lembra
    const leite = r.data.added.find((i: any) => i.name === 'Leite');
    expect((await call(a.client, 'update_shopping_item', { id: leite.id, section: 'bebidas', checked: true })).isError).toBe(false);
    expect((await call(a.client, 'finish_shopping')).data.removed).toBe(1);
    const again = await call(a.client, 'add_shopping_items', { items: [{ name: 'leite' }] });
    expect(again.data.added[0].section).toBe('bebidas');
    expect((await call(a.client, 'add_shopping_items', { items: [{ name: 'LEITE' }] })).data.skipped).toEqual(['LEITE']);
    expect((await call(a.client, 'list_shopping')).data.lists[0].pending.length).toBe(4);
  });

  it('ficha: cria, edita mantendo o id e aparece no histórico', async () => {
    const w = await call(a.client, 'upsert_workout', { name: 'Treino A', exercises: [{ name: 'Supino' }, { name: 'Remada' }] });
    expect(w.isError).toBe(false);
    const [supino] = w.data.workout.exercises;
    expect(supino).not.toHaveProperty('loadKg');
    expect(supino).not.toHaveProperty('restSeconds');
    const e = await call(a.client, 'upsert_workout', { id: w.data.workout.id, name: 'Treino A', exercises: [{ name: 'supino', sets: 5 }] });
    expect(e.data.workout.exercises).toHaveLength(1);
    expect(e.data.workout.exercises[0]).toMatchObject({ id: supino.id, sets: 5 });
    const { data: s } = await db.from('workout_sessions').insert({ user_id: userA, workout_id: w.data.workout.id, workout_name: 'Treino A', day: '2026-10-18' }).select('id').single();
    await db.from('set_logs').insert({ user_id: userA, session_id: s!.id, exercise_id: supino.id, exercise_name: 'Supino', set_index: 1, reps: 10, load_kg: 40 });
    const h = await call(a.client, 'list_workout_history');
    expect(h.data.sessions[0].sets[0]).toMatchObject({ exerciseName: 'Supino', reps: 10 });
    expect(h.data.sessions[0].sets[0]).not.toHaveProperty('loadKg');
  });
});
