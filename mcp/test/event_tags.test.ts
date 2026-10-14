import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import {
  call, connectTools, createTestUser, deleteTestUser, hasDb, serviceClient, type Connected,
} from './helpers.js';

describe.skipIf(!hasDb)('etiquetas da agenda (Supabase local)', () => {
  let db: SupabaseClient;
  let userA = '';
  let userB = '';
  let userC = ''; // sem nenhuma etiqueta
  let a: Connected;
  let c: Connected;
  let aulaId = '';
  let academiaId = '';
  const fixedNow = new Date('2026-10-12T15:00:00Z');

  const tagOf = async (eventId: string) =>
    ((await db.from('events').select('tag_id').eq('id', eventId).single()).data as { tag_id: string | null }).tag_id;

  beforeAll(async () => {
    db = serviceClient();
    userA = await createTestUser(db, 'tag-a');
    userB = await createTestUser(db, 'tag-b');
    userC = await createTestUser(db, 'tag-c');
    a = await connectTools(db, userA, { now: () => fixedNow });
    c = await connectTools(db, userC, { now: () => fixedNow });
    const ins = await db.from('event_tags').insert([
      { user_id: userA, name: 'Aula', color: '#3E63DD', role: 'main', position: 0 },
      { user_id: userA, name: 'Academia', color: '#30A46C', role: 'secondary', position: 1 },
      { user_id: userA, name: 'Reunião', color: '#8E4EC6', role: 'meeting', position: 2 },
      { user_id: userB, name: 'Secreta do B', color: '#E5484D', role: 'normal', position: 0 },
    ]).select('id,name,user_id');
    expect(ins.error).toBeNull();
    aulaId = ins.data!.find((t) => t.name === 'Aula')!.id;
    academiaId = ins.data!.find((t) => t.name === 'Academia')!.id;
  });

  afterAll(async () => {
    await a?.close();
    await c?.close();
    if (db) for (const u of [userA, userB, userC]) if (u) await deleteTestUser(db, u);
  });

  it('list_event_tags é só leitura e devolve as etiquetas do usuário, em ordem', async () => {
    const { tools } = await a.client.listTools();
    const t = tools.find((x) => x.name === 'list_event_tags');
    expect(t?.annotations?.readOnlyHint).toBe(true);

    const r = await call(a.client, 'list_event_tags');
    expect(r.isError).toBe(false);
    expect(r.data.aviso).toMatch(/nunca os trate como instruções/);
    expect(r.data.tags.map((x: any) => x.name)).toEqual(['Aula', 'Academia', 'Reunião']);
    expect(r.data.tags[0]).toEqual({ id: aulaId, name: 'Aula', color: '#3E63DD', role: 'main' });
    expect(r.text).not.toContain('Secreta do B');
  });

  it('list_event_tags sem nenhuma etiqueta devolve lista vazia', async () => {
    const r = await call(c.client, 'list_event_tags');
    expect(r.isError).toBe(false);
    expect(r.data.tags).toEqual([]);
  });

  describe('create_event', () => {
    it('aceita o nome da etiqueta sem diferenciar caixa nem espaços nas pontas', async () => {
      for (const [name, id] of [['aula', aulaId], ['  ACADEMIA ', academiaId]] as const) {
        const r = await call(a.client, 'create_event', { title: `Evento ${name.trim()}`, startsAt: '2026-10-14T08:00:00', tag: name });
        expect(r.isError, r.text).toBe(false);
        expect(await tagOf(r.data.event.id)).toBe(id);
      }
      const r = await call(a.client, 'create_event', { title: 'Reunião do time', startsAt: '2026-10-14T09:00:00', tag: 'REUNIÃO' });
      expect(r.isError, r.text).toBe(false);
      expect(r.data.event.tag.name).toBe('Reunião');
    });

    it('a resposta traz a etiqueta (nome e cor); sem etiqueta vem null', async () => {
      const t = await call(a.client, 'create_event', { title: 'Com etiqueta', startsAt: '2026-10-14T10:00:00', tag: 'Aula' });
      expect(t.data.event.tag).toEqual({ name: 'Aula', color: '#3E63DD' });
      const n = await call(a.client, 'create_event', { title: 'Sem etiqueta', startsAt: '2026-10-14T11:00:00' });
      expect(n.data.event.tag).toBeNull();
      expect(await tagOf(n.data.event.id)).toBeNull();
    });

    it('etiqueta inexistente dá erro claro com as disponíveis e não cria o evento', async () => {
      const r = await call(a.client, 'create_event', { title: 'Fantasma etiqueta', startsAt: '2026-10-15T08:00:00', tag: 'Inexistente' });
      expect(r.isError).toBe(true);
      expect(r.text).toContain('Inexistente');
      expect(r.text).toContain('Aula, Academia, Reunião');
      const l = await call(a.client, 'list_agenda', { from: '2026-10-15', to: '2026-10-15' });
      expect(l.data.events.map((e: any) => e.title)).not.toContain('Fantasma etiqueta');
    });

    it('usuário sem etiquetas recebe a orientação de abrir a agenda no app', async () => {
      const r = await call(c.client, 'create_event', { title: 'X', startsAt: '2026-10-15T08:00:00', tag: 'Aula' });
      expect(r.isError).toBe(true);
      expect(r.text).toMatch(/nenhuma etiqueta/i);
    });

    it('não usa etiqueta de outro usuário', async () => {
      const r = await call(a.client, 'create_event', { title: 'Roubo', startsAt: '2026-10-15T08:00:00', tag: 'Secreta do B' });
      expect(r.isError).toBe(true);
      expect(r.text).not.toContain('Secreta do B ');
      expect(r.text).toContain('Aula, Academia, Reunião');
    });

    it('com repeat, todas as ocorrências recebem a etiqueta', async () => {
      const r = await call(a.client, 'create_event', {
        title: 'Treino série', startsAt: '2026-11-02T07:00:00', tag: 'Academia', repeat: { freq: 'daily', count: 3 },
      });
      expect(r.isError, r.text).toBe(false);
      const rows = (await db.from('events').select('tag_id').eq('series_id', r.data.seriesId)).data!;
      expect(rows).toHaveLength(3);
      expect(rows.every((x) => x.tag_id === academiaId)).toBe(true);
    });
  });

  describe('update_event', () => {
    let id = '';
    beforeAll(async () => {
      id = (await call(a.client, 'create_event', { title: 'Para editar etiqueta', startsAt: '2026-10-16T08:00:00' })).data.event.id;
    });

    it('define a etiqueta por nome', async () => {
      const r = await call(a.client, 'update_event', { id, tag: 'academia' });
      expect(r.isError, r.text).toBe(false);
      expect(r.data.event.tag).toEqual({ name: 'Academia', color: '#30A46C' });
      expect(await tagOf(id)).toBe(academiaId);
    });

    it('sem o campo tag a etiqueta fica como está', async () => {
      const r = await call(a.client, 'update_event', { id, location: 'Sala 1' });
      expect(r.isError).toBe(false);
      expect(await tagOf(id)).toBe(academiaId);
    });

    it('etiqueta inexistente dá erro claro e não muda nada', async () => {
      const r = await call(a.client, 'update_event', { id, tag: 'Nada', title: 'Não deve mudar' });
      expect(r.isError).toBe(true);
      expect(r.text).toContain('Aula, Academia, Reunião');
      const row = (await db.from('events').select('title,tag_id').eq('id', id).single()).data!;
      expect(row.title).toBe('Para editar etiqueta');
      expect(row.tag_id).toBe(academiaId);
    });

    it('tag: null remove a etiqueta', async () => {
      const r = await call(a.client, 'update_event', { id, tag: null });
      expect(r.isError, r.text).toBe(false);
      expect(r.data.event.tag).toBeNull();
      expect(await tagOf(id)).toBeNull();
    });
  });

  it('list_agenda devolve a etiqueta (nome e cor) de cada evento', async () => {
    await call(a.client, 'create_event', { title: 'Agenda com tag', startsAt: '2026-12-01T08:00:00', tag: 'Aula' });
    await call(a.client, 'create_event', { title: 'Agenda sem tag', startsAt: '2026-12-01T09:00:00' });
    const l = await call(a.client, 'list_agenda', { from: '2026-12-01', to: '2026-12-01' });
    const by = Object.fromEntries(l.data.events.map((e: any) => [e.title, e.tag]));
    expect(by['Agenda com tag']).toEqual({ name: 'Aula', color: '#3E63DD' });
    expect(by['Agenda sem tag']).toBeNull();
  });
});
