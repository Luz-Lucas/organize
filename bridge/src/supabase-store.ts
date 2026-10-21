import type { SupabaseClient } from '@supabase/supabase-js';
import { splitTasks, type BriefingInput } from './briefing.js';
import type { Command, CommandKind } from './commands.js';
import type { EchoDevice, Routine, SmartDevice } from './gateway.js';
import type { DeviceAction } from './gateway.js';
import type { PresenceInput } from './presence.js';
import type { ReminderData, ReminderEvent, ReminderFire, ReminderSettings, ReminderTask } from './reminders.js';
import type { AfterMusic, PhoneAlarm, RunStatus, WakeDeviceAction, WakeOverride, WakePlan, WakeRun } from './scheduler.js';
import { zonedDayRange } from './time.js';
import type { WakeStore } from './wake.js';

export type BridgeState = 'ok' | 'auth_required' | 'error';

type Row = Record<string, any>; // eslint-disable-line @typescript-eslint/no-explicit-any

const toCommand = (r: Row): Command => ({
  id: r.id,
  kind: r.kind as CommandKind,
  payload: (r.payload ?? {}) as Record<string, unknown>,
  createdAt: new Date(r.created_at),
});

const AFTER_MUSIC: readonly AfterMusic[] = ['briefing', 'headlines', 'end'];
const PHONE_ALARMS: readonly PhoneAlarm[] = ['never', 'fallback', 'always'];
const DEVICE_ACTIONS: readonly DeviceAction[] = ['turnOn', 'turnOff', 'setBrightness'];
const MAX_ACTION_DELAY_MIN = 30;

const isNum = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v);

/** Lê `device_actions` (jsonb) descartando entradas inválidas, para um dado ruim nunca derrubar o despertar. */
export function toDeviceActions(raw: unknown): WakeDeviceAction[] {
  if (!Array.isArray(raw)) return [];
  const out: WakeDeviceAction[] = [];
  for (const item of raw as unknown[]) {
    if (typeof item !== 'object' || item === null) continue;
    const r = item as Record<string, unknown>;
    if (typeof r.entityId !== 'string' || r.entityId.length === 0) continue;
    if (!DEVICE_ACTIONS.includes(r.action as DeviceAction)) continue;
    const action = r.action as DeviceAction;
    const delay = isNum(r.delayMin) ? Math.round(r.delayMin) : 0;
    const entry: WakeDeviceAction = {
      entityId: r.entityId,
      name: typeof r.name === 'string' && r.name ? r.name : r.entityId,
      action,
      delayMin: Math.min(Math.max(delay, 0), MAX_ACTION_DELAY_MIN),
    };
    if (action === 'setBrightness') {
      if (!isNum(r.brightness)) continue;
      entry.brightness = Math.min(Math.max(Math.round(r.brightness), 0), 100);
    }
    out.push(entry);
  }
  return out;
}

export const toPlan = (r: Row): WakePlan => ({
  id: r.id,
  label: r.label,
  days: r.days,
  time: r.time,
  echoDeviceId: r.echo_device_id,
  spotifyQuery: r.spotify_query,
  musicFirst: r.music_first,
  briefingDelayMin: r.briefing_delay_min,
  briefingDelaySec: isNum(r.briefing_delay_sec) ? r.briefing_delay_sec : null,
  musicStopAfterSec: r.music_stop_after_sec ?? null,
  afterMusic: AFTER_MUSIC.includes(r.after_music) ? r.after_music : 'briefing',
  volume: r.volume,
  fallbackAlarm: r.fallback_alarm,
  enabled: r.enabled,
  includeWeather: r.include_weather !== false,
  deviceActions: toDeviceActions(r.device_actions),
  phoneAlarm: PHONE_ALARMS.includes(r.phone_alarm) ? r.phone_alarm : 'fallback',
});

/** Monta a entrada da presença a partir das linhas de `user_settings` e `user_locations` (qualquer uma pode faltar). */
export function toPresenceSource(settings: Row | null, loc: Row | null): Omit<PresenceInput, 'now' | 'maxAgeMin'> {
  const hasHome = isNum(settings?.home_lat) && isNum(settings?.home_lon);
  const reportedAt = loc ? new Date(loc.reported_at) : null;
  const hasLoc = loc !== null && isNum(loc.lat) && isNum(loc.lon) && reportedAt !== null && !Number.isNaN(reportedAt.getTime());
  return {
    home: hasHome
      ? { lat: settings!.home_lat, lon: settings!.home_lon, radiusM: isNum(settings!.home_radius_m) ? settings!.home_radius_m : 50 }
      : null,
    requireHome: settings?.require_home !== false,
    location: hasLoc
      ? { lat: loc!.lat, lon: loc!.lon, accuracyM: isNum(loc!.accuracy_m) ? loc!.accuracy_m : null, reportedAt: reportedAt! }
      : null,
  };
}

const hhmm = (v: unknown, fallback: string): string => (typeof v === 'string' && /^\d{2}:\d{2}/.test(v) ? v.slice(0, 5) : fallback);
const toMinutesList = (v: unknown, fallback: number[]): number[] =>
  Array.isArray(v) ? (v as unknown[]).filter((x): x is number => isNum(x)) : fallback;

/** Ajustes de lembretes de `user_settings` (linha ausente ou colunas nulas caem nos padrões do banco). */
export const toReminderSettings = (r: Row | null): ReminderData['settings'] => ({
  remindersAlexa: r?.reminders_alexa !== false,
  reminderEcho: typeof r?.reminder_echo === 'string' && r.reminder_echo ? r.reminder_echo : null,
  dndEnabled: r?.dnd_enabled !== false,
  dndStart: hhmm(r?.dnd_start, '23:00'),
  dndEnd: hhmm(r?.dnd_end, '10:00'),
});

export const toReminderTask = (r: Row): ReminderTask => ({
  id: r.id, title: r.title, dueAt: r.due_at ? new Date(r.due_at) : null,
  status: r.status, priority: r.priority, reminders: toMinutesList(r.reminders, [60]),
});

export const toReminderEvent = (r: Row): ReminderEvent => ({
  id: r.id, title: r.title, startsAt: new Date(r.starts_at), allDay: r.all_day === true,
  reminders: toMinutesList(r.reminders, [30]),
});

/** Janelas de carga dos lembretes: o aviso nunca vem depois do item, e o mais antigo é de 1 dia antes. */
const REMINDER_TASK_HORIZON_MS = 48 * 3_600_000;
const REMINDER_EVENT_HORIZON_MS = 26 * 3_600_000;
const REMINDER_BACK_MS = 10 * 60_000;

const toRun = (r: Row): WakeRun => ({
  id: r.id,
  planId: r.plan_id,
  runDate: r.run_date,
  plannedFor: new Date(r.planned_for),
  status: r.status as RunStatus,
  fallbackHandle: r.fallback_handle,
});

export const toOverride = (r: Row): WakeOverride => ({
  planId: r.plan_id,
  runDate: r.run_date,
  skip: r.skip === true,
  time: typeof r.time === 'string' ? r.time : null,
});

export class SupabaseStore implements WakeStore {
  constructor(
    private readonly db: SupabaseClient,
    private readonly userId: string,
    private readonly log: (m: string) => void,
  ) {}

  private check<T>(res: { data: T; error: { message: string } | null }): T {
    if (res.error) throw new Error(res.error.message);
    return res.data;
  }

  async briefingInput(now: Date, timeZone: string): Promise<BriefingInput> {
    const { start, end } = zonedDayRange(now, timeZone);
    const events = this.check(await this.db.from('events')
      .select('title, starts_at, ends_at, all_day, location')
      .eq('user_id', this.userId)
      .lt('starts_at', end.toISOString())
      // mesma regra do app (eventsOnDay): termina depois do início do dia OU começa a partir dele
      // (cobre eventos de duração zero à meia-noite local)
      .or(`ends_at.gt.${start.toISOString()},starts_at.gte.${start.toISOString()}`)
      .order('starts_at')) as Row[];
    const tasks = this.check(await this.db.from('tasks')
      .select('title, due_at')
      .eq('user_id', this.userId)
      .neq('status', 'done')
      .not('due_at', 'is', null)
      .lt('due_at', end.toISOString())
      .order('due_at')) as Row[];
    const { overdue, dueToday } = splitTasks(tasks.map((t) => ({ title: t.title, dueAt: new Date(t.due_at) })), start);

    let news: BriefingInput['news'] = [];
    try {
      const prefs = this.check(await this.db.from('news_prefs')
        .select('briefing_count').eq('user_id', this.userId).maybeSingle()) as Row | null;
      const count = (prefs?.briefing_count as number | undefined) ?? 3;
      if (count > 0) {
        const rows = this.check(await this.db.rpc('news_feed', { p_user: this.userId, p_limit: count })) as Row[];
        news = rows.map((r) => ({ title: r.title, source: r.source_name }));
      }
    } catch (e) {
      this.log(`notícias indisponíveis: ${(e as Error).message}`);
    }

    return {
      now,
      timeZone,
      events: events.map((e) => ({
        title: e.title, startsAt: new Date(e.starts_at), endsAt: new Date(e.ends_at),
        allDay: e.all_day, location: e.location,
      })),
      overdue,
      dueToday,
      news,
    };
  }

  /** Cria uma tarefa manual (a fazer) com a prioridade dada, como o `create_task` do MCP. */
  async addTask(task: { title: string; dueAt: Date | null; priority: 'baixa' | 'media' | 'alta' }): Promise<void> {
    this.check(await this.db.from('tasks').insert({
      user_id: this.userId, title: task.title, description: '', status: 'todo', priority: task.priority,
      due_at: task.dueAt?.toISOString() ?? null, completed_at: null, space_id: null, note_id: null, source: 'manual',
    }));
  }

  /** Tarefas abertas com prazo nas próximas 48 h, eventos das próximas 26 h e os ajustes de lembretes. */
  async loadReminderData(now: Date): Promise<ReminderData> {
    const from = new Date(now.getTime() - REMINDER_BACK_MS).toISOString();
    const tasks = this.check(await this.db.from('tasks')
      .select('id, title, due_at, status, priority, reminders')
      .eq('user_id', this.userId).neq('status', 'done').not('due_at', 'is', null)
      .gte('due_at', from).lte('due_at', new Date(now.getTime() + REMINDER_TASK_HORIZON_MS).toISOString())
      .order('due_at')) as Row[];
    const events = this.check(await this.db.from('events')
      .select('id, title, starts_at, all_day, reminders')
      .eq('user_id', this.userId).eq('all_day', false)
      .gte('starts_at', from).lte('starts_at', new Date(now.getTime() + REMINDER_EVENT_HORIZON_MS).toISOString())
      .order('starts_at')) as Row[];
    const settings = this.check(await this.db.from('user_settings')
      .select('reminders_alexa, reminder_echo, dnd_enabled, dnd_start, dnd_end')
      .eq('user_id', this.userId).maybeSingle()) as Row | null;
    return { tasks: tasks.map(toReminderTask), events: events.map(toReminderEvent), settings: toReminderSettings(settings) };
  }

  /** Registra o aviso falado; false se já estava registrado (único por item, horário e canal). */
  async claimReminder(f: ReminderFire): Promise<boolean> {
    const rows = this.check(await this.db.from('reminder_deliveries')
      .upsert({ user_id: this.userId, kind: f.kind, item_id: f.itemId, fire_at: f.fireAt.toISOString(), channel: 'alexa' },
        { onConflict: 'user_id,kind,item_id,fire_at,channel', ignoreDuplicates: true })
      .select('id')) as Row[];
    return rows.length > 0;
  }

  async listWakePlans(): Promise<WakePlan[]> {
    return (this.check(await this.db.from('wake_plans').select('*').eq('user_id', this.userId)) as Row[]).map(toPlan);
  }

  async listWakeRuns(sinceDate: string): Promise<WakeRun[]> {
    return (this.check(await this.db.from('wake_runs').select('*')
      .eq('user_id', this.userId).gte('run_date', sinceDate)) as Row[]).map(toRun);
  }

  /** Exceções de data ("só amanhã") do usuário entre `fromDate` e `toDate`, inclusive. */
  async loadOverrides(fromDate: string, toDate: string): Promise<WakeOverride[]> {
    return (this.check(await this.db.from('wake_overrides').select('plan_id, run_date, skip, time')
      .eq('user_id', this.userId).gte('run_date', fromDate).lte('run_date', toDate)
      .order('run_date')) as Row[]).map(toOverride);
  }

  /** Apaga exceções de datas anteriores a `beforeDate` (limpeza; best effort no chamador). */
  async purgeOldOverrides(beforeDate: string): Promise<void> {
    this.check(await this.db.from('wake_overrides').delete()
      .eq('user_id', this.userId).lt('run_date', beforeDate));
  }

  async armRun(planId: string, runDate: string, plannedFor: Date, fallbackHandle: string): Promise<void> {
    this.check(await this.db.from('wake_runs').upsert({
      user_id: this.userId, plan_id: planId, run_date: runDate, planned_for: plannedFor.toISOString(),
      status: 'armed', fallback_handle: fallbackHandle, note: null,
    }, { onConflict: 'plan_id,run_date' }));
  }

  async setRunStatus(runId: string, status: RunStatus, note: string | null = null): Promise<void> {
    this.check(await this.db.from('wake_runs').update({ status, note })
      .eq('id', runId).eq('user_id', this.userId));
  }

  async claimRun(planId: string, runDate: string, plannedFor: Date): Promise<boolean> {
    return Boolean(this.check(await this.db.rpc('claim_wake_run', {
      p_user: this.userId, p_plan: planId, p_date: runDate, p_planned: plannedFor.toISOString(),
    })));
  }

  /** Casa e última localização do celular, para decidir a presença na hora do despertar. */
  async loadPresenceInput(): Promise<Omit<PresenceInput, 'now' | 'maxAgeMin'>> {
    const settings = this.check(await this.db.from('user_settings')
      .select('home_lat, home_lon, home_radius_m, require_home')
      .eq('user_id', this.userId).maybeSingle()) as Row | null;
    const loc = this.check(await this.db.from('user_locations')
      .select('lat, lon, accuracy_m, reported_at')
      .eq('user_id', this.userId).maybeSingle()) as Row | null;
    return toPresenceSource(settings, loc);
  }

  async finishRun(planId: string, runDate: string, status: 'done' | 'failed' | 'skipped', note: string): Promise<void> {
    this.check(await this.db.from('wake_runs').update({ status, note })
      .eq('user_id', this.userId).eq('plan_id', planId).eq('run_date', runDate));
  }

  async pendingCommands(): Promise<Command[]> {
    return (this.check(await this.db.from('alexa_commands').select('id, kind, payload, created_at')
      .eq('user_id', this.userId).eq('status', 'pending').order('created_at')) as Row[]).map(toCommand);
  }

  async claimCommand(id: string): Promise<boolean> {
    return Boolean(this.check(await this.db.rpc('claim_command', { p_user: this.userId, p_id: id })));
  }

  async finishCommand(id: string, status: 'done' | 'failed' | 'expired', result: string): Promise<void> {
    this.check(await this.db.from('alexa_commands')
      .update({ status, result, finished_at: new Date().toISOString() })
      .eq('id', id).eq('user_id', this.userId));
  }

  onNewCommand(cb: (cmd: Command) => void): () => void {
    const channel = this.db.channel('alexa-commands')
      .on('postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'alexa_commands', filter: `user_id=eq.${this.userId}` },
        (payload) => cb(toCommand(payload.new as Row)))
      .subscribe((status) => {
        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
          this.log(`realtime de comandos indisponível (${status}); a varredura de 15 s cobre`);
        }
      });
    return () => { void this.db.removeChannel(channel); };
  }

  private async deleteStale(table: string, keep: string[]): Promise<void> {
    let query = this.db.from(table).delete().eq('user_id', this.userId);
    if (keep.length) query = query.not('id', 'in', `(${keep.map((id) => `"${id.replace(/"/g, '\\"')}"`).join(',')})`);
    this.check(await query);
  }

  async saveDevices(echos: EchoDevice[], smart: SmartDevice[]): Promise<void> {
    const now = new Date().toISOString();
    const rows = [
      ...echos.map((e) => ({ user_id: this.userId, id: e.id, name: e.name, kind: 'echo', operations: [], online: e.online, updated_at: now })),
      ...smart.map((s) => ({ user_id: this.userId, id: s.id, name: s.name, kind: 'smart', operations: s.operations, online: true, updated_at: now })),
    ];
    if (rows.length) this.check(await this.db.from('alexa_devices').upsert(rows, { onConflict: 'user_id,id' }));
    await this.deleteStale('alexa_devices', rows.map((r) => r.id));
  }

  async saveRoutines(routines: Routine[]): Promise<void> {
    const now = new Date().toISOString();
    const rows = routines.map((r) => ({ user_id: this.userId, id: r.id, name: r.name, updated_at: now }));
    if (rows.length) this.check(await this.db.from('alexa_routines').upsert(rows, { onConflict: 'user_id,id' }));
    await this.deleteStale('alexa_routines', rows.map((r) => r.id));
  }

  async setStatus(state: BridgeState, message: string | null): Promise<void> {
    this.check(await this.db.from('alexa_bridge_status').upsert({
      user_id: this.userId, state, message, last_seen: new Date().toISOString(),
    }));
  }

  /** Recuperação de queda: comandos presos em 'running' há mais de `olderThanMs` viram 'failed'. */
  async sweepStuckCommands(olderThanMs = 10 * 60_000): Promise<number> {
    const cutoff = new Date(Date.now() - olderThanMs).toISOString();
    const rows = this.check(await this.db.from('alexa_commands')
      .update({ status: 'failed', result: 'ponte reiniciou durante a execução', finished_at: new Date().toISOString() })
      .eq('user_id', this.userId).eq('status', 'running').lt('started_at', cutoff)
      .select('id')) as Row[];
    return rows.length;
  }

  async heartbeat(): Promise<void> {
    this.check(await this.db.from('alexa_bridge_status')
      .update({ last_seen: new Date().toISOString() }).eq('user_id', this.userId));
  }
}
