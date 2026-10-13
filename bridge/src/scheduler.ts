import type { DeviceAction } from './gateway.js';
import { addDays, localParts, zonedTime } from './time.js';

export type AfterMusic = 'briefing' | 'headlines' | 'end';
export type PhoneAlarm = 'never' | 'fallback' | 'always';

/** Ação num dispositivo inteligente executada durante o despertar, após `delayMin` minutos. */
export interface WakeDeviceAction {
  entityId: string;
  name: string;
  action: DeviceAction;
  /** 0-100; só para setBrightness. */
  brightness?: number;
  delayMin: number;
}

export interface WakePlan {
  id: string;
  label: string;
  days: number[];
  time: string;
  echoDeviceId: string;
  spotifyQuery: string | null;
  musicFirst: boolean;
  briefingDelayMin: number;
  /** Espera em segundos entre a música e o resumo; null = usa briefingDelayMin (minutos). */
  briefingDelaySec: number | null;
  /** Segundos de música antes de parar; null = não para. */
  musicStopAfterSec: number | null;
  /** O que vem depois da música (só com musicFirst). */
  afterMusic: AfterMusic;
  volume: number;
  fallbackAlarm: boolean;
  enabled: boolean;
  /** Fala a previsão do tempo logo depois da data. */
  includeWeather: boolean;
  /** Ações de dispositivos, em paralelo com a música e a fala. */
  deviceActions: WakeDeviceAction[];
  /** Só usado na fase 2 (alarme no celular). */
  phoneAlarm: PhoneAlarm;
}

/** `skipped`: o usuário estava fora de casa; é um estado final, nunca rearmado nem disparado de novo. */
export type RunStatus = 'armed' | 'running' | 'done' | 'failed' | 'missed' | 'cancelled' | 'skipped';

export interface WakeRun {
  id: string;
  planId: string | null;
  runDate: string;
  plannedFor: Date;
  status: RunStatus;
  fallbackHandle: string | null;
}

/** Exceção de uma data só ("só amanhã"): pula o despertar ou troca o horário daquele dia. */
export interface WakeOverride {
  planId: string;
  /** Data local YYYY-MM-DD. */
  runDate: string;
  skip: boolean;
  /** HH:MM[:SS]; vale mesmo que o dia da semana não esteja em `plan.days`. */
  time: string | null;
}

export type WakeAction =
  | { type: 'arm'; plan: WakePlan; runDate: string; plannedFor: Date; fallbackAt: Date }
  | { type: 'rearm'; run: WakeRun; plan: WakePlan; plannedFor: Date; fallbackAt: Date }
  | { type: 'cancel'; run: WakeRun }
  | { type: 'miss'; run: WakeRun }
  | { type: 'fire'; plan: WakePlan; runDate: string; plannedFor: Date; run: WakeRun | null };

export interface SchedulerOptions { graceMin: number; fallbackDelayMin: number; armAheadHours: number }
export const DEFAULT_OPTIONS: SchedulerOptions = { graceMin: 15, fallbackDelayMin: 10, armAheadHours: 24 };

const MIN = 60_000;

export function occurrence(
  plan: WakePlan,
  runDate: string,
  timeZone: string,
  overrides: readonly WakeOverride[] = [],
): Date | null {
  const override = overrides.find((o) => o.planId === plan.id && o.runDate === runDate);
  if (override?.skip) return null;
  if (override?.time) return zonedTime(runDate, override.time.slice(0, 5), timeZone);
  const weekday = localParts(zonedTime(runDate, '12:00', timeZone), timeZone).weekday;
  return plan.days.includes(weekday) ? zonedTime(runDate, plan.time.slice(0, 5), timeZone) : null;
}

export function planWakeActions(
  plans: WakePlan[],
  runs: WakeRun[],
  now: Date,
  timeZone: string,
  opts: SchedulerOptions = DEFAULT_OPTIONS,
  overrides: readonly WakeOverride[] = [],
): WakeAction[] {
  const actions: WakeAction[] = [];
  const planById = new Map(plans.map((p) => [p.id, p]));
  const runByKey = new Map(runs.filter((r) => r.planId).map((r) => [`${r.planId}:${r.runDate}`, r]));
  const grace = opts.graceMin * MIN;
  const fallbackAt = (occ: Date) => new Date(occ.getTime() + opts.fallbackDelayMin * MIN);

  // 1) Manutenção dos alarmes reserva já armados
  for (const run of runs) {
    if (run.status !== 'armed') continue;
    const plan = run.planId ? planById.get(run.planId) : undefined;
    const occ = plan && plan.enabled && plan.fallbackAlarm ? occurrence(plan, run.runDate, timeZone, overrides) : null;
    if (!plan || !occ) {
      actions.push({ type: 'cancel', run });
      continue;
    }
    if (now.getTime() > occ.getTime() + grace) {
      actions.push({ type: 'miss', run });
      continue;
    }
    if (now.getTime() >= occ.getTime()) continue; // na janela: o disparo abaixo cuida
    if (occ.getTime() !== run.plannedFor.getTime()) {
      actions.push({ type: 'rearm', run, plan, plannedFor: occ, fallbackAt: fallbackAt(occ) });
    }
  }

  // 2) Disparos e novos alarmes reserva (ontem cobre planos perto da meia-noite)
  const today = localParts(now, timeZone).date;
  for (const plan of plans) {
    if (!plan.enabled) continue;
    for (const runDate of [addDays(today, -1), today, addDays(today, 1)]) {
      const occ = occurrence(plan, runDate, timeZone, overrides);
      if (!occ) continue;
      const run = runByKey.get(`${plan.id}:${runDate}`) ?? null;
      const delta = now.getTime() - occ.getTime();
      const claimable = !run || run.status === 'armed' || run.status === 'cancelled';
      if (delta >= 0 && delta <= grace) {
        if (claimable) actions.push({ type: 'fire', plan, runDate, plannedFor: occ, run });
      } else if (
        delta < 0 &&
        -delta <= opts.armAheadHours * 60 * MIN &&
        plan.fallbackAlarm &&
        (!run || run.status === 'cancelled')
      ) {
        actions.push({ type: 'arm', plan, runDate, plannedFor: occ, fallbackAt: fallbackAt(occ) });
      }
    }
  }
  return actions;
}
