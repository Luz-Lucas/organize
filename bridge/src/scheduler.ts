import { addDays, localParts, zonedTime } from './time.js';

export interface WakePlan {
  id: string;
  label: string;
  days: number[];
  time: string;
  echoDeviceId: string;
  spotifyQuery: string | null;
  musicFirst: boolean;
  briefingDelayMin: number;
  volume: number;
  fallbackAlarm: boolean;
  enabled: boolean;
}

export type RunStatus = 'armed' | 'running' | 'done' | 'failed' | 'missed' | 'cancelled';

export interface WakeRun {
  id: string;
  planId: string | null;
  runDate: string;
  plannedFor: Date;
  status: RunStatus;
  fallbackHandle: string | null;
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

export function occurrence(plan: WakePlan, runDate: string, timeZone: string): Date | null {
  const weekday = localParts(zonedTime(runDate, '12:00', timeZone), timeZone).weekday;
  return plan.days.includes(weekday) ? zonedTime(runDate, plan.time.slice(0, 5), timeZone) : null;
}

export function planWakeActions(
  plans: WakePlan[],
  runs: WakeRun[],
  now: Date,
  timeZone: string,
  opts: SchedulerOptions = DEFAULT_OPTIONS,
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
    const occ = plan && plan.enabled && plan.fallbackAlarm ? occurrence(plan, run.runDate, timeZone) : null;
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
      const occ = occurrence(plan, runDate, timeZone);
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
