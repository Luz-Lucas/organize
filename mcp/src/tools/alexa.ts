import { z } from 'zod';
import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import type { CallToolResult } from '@modelcontextprotocol/sdk/types.js';
import type { ToolContext } from './index.js';
import { ACT, READ, UserError, check, fail, ok, requireEcho, requireRow, safe } from './util.js';

type Row = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any

export interface AlexaOptions {
  /** Tempo máximo esperando a ponte (padrão 20 000 ms). */
  waitMs?: number;
  /** Intervalo entre consultas (padrão 1 000 ms). */
  pollMs?: number;
}

const FINAL = new Set(['done', 'failed', 'expired']);
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export function registerAlexa(server: McpServer, ctx: ToolContext, opts: AlexaOptions = {}): void {
  const waitMs = opts.waitMs ?? 20_000;
  const pollMs = opts.pollMs ?? 1_000;

  async function send(kind: 'speak' | 'routine' | 'device', payload: Record<string, unknown>): Promise<CallToolResult> {
    const cmd = check(await ctx.db.from('alexa_commands').insert({
      user_id: ctx.userId, kind, payload, status: 'pending',
    }).select('id').single()) as Row;
    const deadline = Date.now() + waitMs;
    for (;;) {
      const cur = check(await ctx.db.from('alexa_commands').select('status,result')
        .eq('id', cmd.id).eq('user_id', ctx.userId).maybeSingle()) as Row | null;
      if (cur && FINAL.has(cur.status)) {
        const body = { commandId: cmd.id, status: cur.status, result: cur.result };
        if (cur.status === 'done') return ok(body);
        return { isError: true, content: [{ type: 'text', text: JSON.stringify(body) }] };
      }
      if (Date.now() >= deadline) break;
      await sleep(Math.min(pollMs, Math.max(0, deadline - Date.now())));
    }
    return ok({ commandId: cmd.id, status: 'pending', note: 'a ponte ainda não respondeu' });
  }

  server.registerTool('list_alexa_devices', {
    title: 'Listar dispositivos Alexa',
    description: 'Dispositivos Echo e inteligentes sincronizados (exceto os ocultos no app). Use o `id` nas outras ferramentas Alexa.',
    inputSchema: {},
    annotations: READ,
  }, safe(async () => {
    const [devs, st] = await Promise.all([
      ctx.db.from('alexa_devices').select('*').eq('user_id', ctx.userId).order('name', { ascending: true }),
      ctx.db.from('user_settings').select('hidden_alexa_devices').eq('user_id', ctx.userId).maybeSingle(),
    ]);
    const rows = check(devs) as Row[];
    const hidden = new Set<string>(((check(st) as Row | null)?.hidden_alexa_devices as string[] | undefined) ?? []);
    return ok({
      devices: rows.filter((d) => !hidden.has(d.id))
        .map((d) => ({ id: d.id, name: d.name, kind: d.kind, operations: d.operations, online: d.online })),
    });
  }));

  server.registerTool('list_alexa_routines', {
    title: 'Listar rotinas Alexa',
    description: 'Rotinas da Alexa sincronizadas.',
    inputSchema: {},
    annotations: READ,
  }, safe(async () => {
    const rows = check(await ctx.db.from('alexa_routines').select('*').eq('user_id', ctx.userId).order('name', { ascending: true })) as Row[];
    return ok({ routines: rows.map((r) => ({ id: r.id, name: r.name })) });
  }));

  server.registerTool('alexa_speak', {
    title: 'Falar no Echo',
    description: 'Faz um Echo falar um texto em voz alta. Age na casa: confirme com o usuário. Espera até ~20 s pela ponte.',
    inputSchema: { echoDeviceId: z.string().min(1).max(200), text: z.string().trim().min(1).max(2000) },
    annotations: ACT,
  }, safe(async (a) => {
    await requireEcho(ctx, a.echoDeviceId);
    return send('speak', { echoDeviceId: a.echoDeviceId, text: a.text });
  }));

  server.registerTool('alexa_run_routine', {
    title: 'Executar rotina Alexa',
    description: 'Executa uma rotina da Alexa num Echo. Age na casa: confirme com o usuário. Espera até ~20 s pela ponte.',
    inputSchema: { routineId: z.string().min(1).max(200), echoDeviceId: z.string().min(1).max(200) },
    annotations: ACT,
  }, safe(async (a) => {
    await requireRow(ctx, 'alexa_routines', a.routineId, 'Rotina');
    await requireEcho(ctx, a.echoDeviceId);
    return send('routine', { routineId: a.routineId, echoDeviceId: a.echoDeviceId });
  }));

  server.registerTool('alexa_device', {
    title: 'Controlar dispositivo inteligente',
    description: 'Liga (`turnOn`), desliga (`turnOff`) ou ajusta o brilho (`setBrightness`, 0–100) de um dispositivo inteligente. Age na casa: confirme com o usuário.',
    inputSchema: {
      deviceId: z.string().min(1).max(200),
      action: z.enum(['turnOn', 'turnOff', 'setBrightness']),
      brightness: z.number().int().min(0).max(100).optional(),
    },
    annotations: ACT,
  }, safe(async (a) => {
    if (a.action === 'setBrightness' && a.brightness === undefined) {
      return fail('Informe o brilho (0 a 100) para setBrightness.');
    }
    const dev = await requireRow(ctx, 'alexa_devices', a.deviceId, 'Dispositivo');
    if (dev.kind !== 'smart') throw new UserError(`"${dev.name}" não é um dispositivo inteligente.`);
    const payload: Record<string, unknown> = { entityId: a.deviceId, action: a.action };
    if (a.action === 'setBrightness') payload.brightness = a.brightness;
    return send('device', payload);
  }));
}
