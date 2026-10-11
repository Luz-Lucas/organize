import { z } from 'zod';
import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import type { ToolContext } from './index.js';
import { ACT, READ, UserError, check, ok, okData, requireEcho, safe } from './util.js';

type Row = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any

const time = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$/, 'use HH:MM');
const days = z.array(z.number().int().min(1).max(7)).min(1).max(7);

function planOut(r: Row) {
  return {
    id: r.id, label: r.label, days: r.days, time: String(r.time).slice(0, 5), echoDeviceId: r.echo_device_id,
    spotifyQuery: r.spotify_query, musicFirst: r.music_first, briefingDelayMin: r.briefing_delay_min,
    volume: r.volume, fallbackAlarm: r.fallback_alarm, enabled: r.enabled,
  };
}

export function registerWake(server: McpServer, ctx: ToolContext): void {
  server.registerTool('list_wake_plans', {
    title: 'Listar despertares',
    description: 'Lista os despertares configurados. `days` usa 1 = segunda … 7 = domingo.',
    inputSchema: {},
    annotations: READ,
  }, safe(async () => {
    const rows = check(await ctx.db.from('wake_plans').select('*').eq('user_id', ctx.userId).order('time', { ascending: true })) as Row[];
    return okData({ wakePlans: rows.map(planOut) });
  }));

  server.registerTool('upsert_wake_plan', {
    title: 'Criar ou editar despertar',
    description:
      'Sem `id`, cria um despertar (exige label, days, time e echoDeviceId). Com `id`, altera só os campos informados. ' +
      '`days`: 1 = segunda … 7 = domingo; `time`: HH:MM no fuso do usuário; `volume` 0–100; `briefingDelayMin` 0–30. ' +
      'Age na casa (o Echo vai falar/tocar no horário): confirme com o usuário. `echoDeviceId` precisa ser um Echo de list_alexa_devices.',
    inputSchema: {
      id: z.string().uuid().optional(), label: z.string().trim().min(1).max(100).optional(), days: days.optional(),
      time: time.optional(), echoDeviceId: z.string().min(1).max(200).optional(),
      spotifyQuery: z.string().max(200).nullable().optional(), musicFirst: z.boolean().optional(),
      briefingDelayMin: z.number().int().min(0).max(30).optional(), volume: z.number().int().min(0).max(100).optional(),
      fallbackAlarm: z.boolean().optional(), enabled: z.boolean().optional(),
    },
    annotations: { ...ACT, idempotentHint: true },
  }, safe(async (a) => {
    if (a.echoDeviceId !== undefined) await requireEcho(ctx, a.echoDeviceId);
    const f: Row = {};
    if (a.label !== undefined) f.label = a.label;
    if (a.days !== undefined) f.days = [...new Set(a.days)].sort();
    if (a.time !== undefined) f.time = a.time;
    if (a.echoDeviceId !== undefined) f.echo_device_id = a.echoDeviceId;
    if (a.spotifyQuery !== undefined) f.spotify_query = a.spotifyQuery || null;
    if (a.musicFirst !== undefined) f.music_first = a.musicFirst;
    if (a.briefingDelayMin !== undefined) f.briefing_delay_min = a.briefingDelayMin;
    if (a.volume !== undefined) f.volume = a.volume;
    if (a.fallbackAlarm !== undefined) f.fallback_alarm = a.fallbackAlarm;
    if (a.enabled !== undefined) f.enabled = a.enabled;
    if (a.id) {
      if (Object.keys(f).length === 0) throw new UserError('Nada para alterar: informe ao menos um campo.');
      const rows = check(await ctx.db.from('wake_plans').update(f).eq('id', a.id).eq('user_id', ctx.userId).select('*')) as Row[];
      if (rows.length === 0) throw new UserError('Despertar não encontrado.');
      return ok({ wakePlan: planOut(rows[0]) });
    }
    for (const k of ['label', 'days', 'time', 'echo_device_id']) {
      if (f[k] === undefined) throw new UserError('Para criar um despertar informe label, days, time e echoDeviceId.');
    }
    const row = check(await ctx.db.from('wake_plans').insert({ ...f, user_id: ctx.userId }).select('*').single());
    return ok({ wakePlan: planOut(row as Row) });
  }));
}
