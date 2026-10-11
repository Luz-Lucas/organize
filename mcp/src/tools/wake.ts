import { z } from 'zod';
import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import type { ToolContext } from './index.js';
import { ACT, READ, UserError, check, ok, okData, requireEcho, requireRow, safe } from './util.js';

type Row = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any

const time = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$/, 'use HH:MM');
const days = z.array(z.number().int().min(1).max(7)).min(1).max(7);

const deviceAction = z.object({
  entityId: z.string().min(1).max(200),
  action: z.enum(['turnOn', 'turnOff', 'setBrightness']),
  brightness: z.number().int().min(0).max(100).optional(),
  delayMin: z.number().int().min(0).max(30).optional(),
});

function planOut(r: Row) {
  return {
    id: r.id, label: r.label, days: r.days, time: String(r.time).slice(0, 5), echoDeviceId: r.echo_device_id,
    spotifyQuery: r.spotify_query, musicFirst: r.music_first, briefingDelayMin: r.briefing_delay_min,
    briefingDelaySec: r.briefing_delay_sec ?? null, musicStopAfterSec: r.music_stop_after_sec ?? null,
    afterMusic: r.after_music ?? 'briefing', includeWeather: r.include_weather !== false,
    deviceActions: Array.isArray(r.device_actions) ? r.device_actions : [],
    volume: r.volume, fallbackAlarm: r.fallback_alarm, enabled: r.enabled,
  };
}

/** Ações de dispositivos no formato do banco; só dispositivos inteligentes do usuário (o nome vem do cadastro, não do cliente). */
async function resolveDeviceActions(ctx: ToolContext, input: z.infer<typeof deviceAction>[]): Promise<Row[]> {
  const out: Row[] = [];
  const names = new Map<string, string>();
  for (const d of input) {
    if (d.action === 'setBrightness' && d.brightness === undefined) {
      throw new UserError('Informe o brilho (0 a 100) para setBrightness.');
    }
    if (!names.has(d.entityId)) {
      const dev = await requireRow(ctx, 'alexa_devices', d.entityId, 'Dispositivo');
      if (dev.kind !== 'smart') throw new UserError(`"${dev.name}" não é um dispositivo inteligente.`);
      names.set(d.entityId, String(dev.name));
    }
    const entry: Row = { entityId: d.entityId, name: names.get(d.entityId), action: d.action, delayMin: d.delayMin ?? 0 };
    if (d.action === 'setBrightness') entry.brightness = d.brightness;
    out.push(entry);
  }
  return out;
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
      '`briefingDelaySec` 0–1800 (espera em segundos entre a música e o resumo; tem prioridade sobre briefingDelayMin; null = usar os minutos). ' +
      '`musicStopAfterSec` 5–600 (para a música após N segundos; null = não parar). `afterMusic`: o que vem depois da música — ' +
      '"briefing" (resumo), "headlines" (só manchetes) ou "end" (encerrar; exige `spotifyQuery`, e só vale se a música de fato tocou). ' +
      '`includeWeather` fala a previsão do tempo. `deviceActions`: ações em dispositivos inteligentes de list_alexa_devices ' +
      '(`entityId`, `action` turnOn|turnOff|setBrightness, `brightness` 0–100, `delayMin` 0–30); [] limpa. ' +
      'Age na casa (o Echo vai falar/tocar no horário): confirme com o usuário. `echoDeviceId` precisa ser um Echo de list_alexa_devices.',
    inputSchema: {
      id: z.string().uuid().optional(), label: z.string().trim().min(1).max(100).optional(), days: days.optional(),
      time: time.optional(), echoDeviceId: z.string().min(1).max(200).optional(),
      spotifyQuery: z.string().max(200).nullable().optional(), musicFirst: z.boolean().optional(),
      briefingDelayMin: z.number().int().min(0).max(30).optional(), volume: z.number().int().min(0).max(100).optional(),
      briefingDelaySec: z.number().int().min(0).max(1800).nullable().optional(),
      musicStopAfterSec: z.number().int().min(5).max(600).nullable().optional(),
      afterMusic: z.enum(['briefing', 'headlines', 'end']).optional(),
      includeWeather: z.boolean().optional(),
      deviceActions: z.array(deviceAction).max(10).optional(),
      fallbackAlarm: z.boolean().optional(), enabled: z.boolean().optional(),
    },
    annotations: { ...ACT, idempotentHint: true },
  }, safe(async (a) => {
    if (a.echoDeviceId !== undefined) await requireEcho(ctx, a.echoDeviceId);
    const f: Row = {};
    // "Encerrar depois da música" só faz sentido com uma busca do Spotify; senão ninguém falaria nada ao despertar.
    if (a.afterMusic === 'end' || (a.id && a.spotifyQuery !== undefined)) {
      let query: string | null | undefined = a.spotifyQuery;
      let after: string | undefined = a.afterMusic;
      if (a.id && (query === undefined || after === undefined)) {
        const cur = check(await ctx.db.from('wake_plans').select('spotify_query, after_music').eq('id', a.id).eq('user_id', ctx.userId).maybeSingle()) as Row | null;
        if (!cur) throw new UserError('Despertar não encontrado.');
        if (query === undefined) query = cur.spotify_query;
        after ??= cur.after_music;
      }
      if (after === 'end' && !query?.trim()) {
        throw new UserError('Para encerrar depois da música, escolha uma busca do Spotify (spotifyQuery).');
      }
    }
    const deviceActions = a.deviceActions === undefined ? undefined : await resolveDeviceActions(ctx, a.deviceActions);
    if (a.label !== undefined) f.label = a.label;
    if (a.days !== undefined) f.days = [...new Set(a.days)].sort();
    if (a.time !== undefined) f.time = a.time;
    if (a.echoDeviceId !== undefined) f.echo_device_id = a.echoDeviceId;
    if (a.spotifyQuery !== undefined) f.spotify_query = a.spotifyQuery || null;
    if (a.musicFirst !== undefined) f.music_first = a.musicFirst;
    if (a.briefingDelayMin !== undefined) {
      f.briefing_delay_min = a.briefingDelayMin;
      // Só os minutos informados: a espera em segundos antiga não pode continuar mandando.
      if (a.briefingDelaySec === undefined) f.briefing_delay_sec = null;
    }
    if (a.briefingDelaySec !== undefined) f.briefing_delay_sec = a.briefingDelaySec;
    if (a.musicStopAfterSec !== undefined) f.music_stop_after_sec = a.musicStopAfterSec;
    if (a.afterMusic !== undefined) f.after_music = a.afterMusic;
    if (a.includeWeather !== undefined) f.include_weather = a.includeWeather;
    if (deviceActions !== undefined) f.device_actions = deviceActions;
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
