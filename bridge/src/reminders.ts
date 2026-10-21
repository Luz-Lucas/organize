import { chunkSpeech } from './briefing.js';
import { AlexaAuthError, type AlexaGateway } from './gateway.js';
import type { PresenceState } from './presence.js';
import { addDays, localParts, zonedTime } from './time.js';

/** Valores aceitos em `reminders` (minutos antes): 1 dia, 1 hora, 30 min, 15 min. */
export type ReminderMinutes = 1440 | 60 | 30 | 15;

export interface ReminderTask {
  id: string;
  title: string;
  dueAt: Date | null;
  status: string;
  priority: string;
  reminders: number[];
}
export interface ReminderEvent {
  id: string;
  title: string;
  startsAt: Date;
  allDay: boolean;
  reminders: number[];
}
export interface ReminderItems { tasks: ReminderTask[]; events: ReminderEvent[] }

/** Não perturbe; `dndStart`/`dndEnd` em "HH:MM" (ou "HH:MM:SS", como o Postgres devolve `time`). */
export interface ReminderSettings { dndEnabled: boolean; dndStart: string; dndEnd: string }

export interface ReminderFire {
  kind: 'task' | 'event';
  itemId: string;
  title: string;
  /** Quando o aviso deve soar (já ajustado pelo não perturbe). */
  fireAt: Date;
  /** Horário do item (início do evento, prazo da tarefa; 23:59 do dia para tarefa só com data). */
  itemAt: Date;
  /** Tarefa só com data (prazo às 23:59 local). */
  dateOnly: boolean;
}

/** Tarefa só com data avisa neste horário local do dia do prazo (só se prioridade alta). */
export const DATE_ONLY_HOUR = '10:00';
const DATE_ONLY_MINUTES = 23 * 60 + 59;

const hhmmToMinutes = (s: string): number => {
  const [h, m] = s.split(':').map(Number);
  return h * 60 + m;
};

/**
 * Passa o aviso para o fim do não perturbe quando ele cai dentro do intervalo [início, fim)
 * (que pode atravessar a meia-noite). Devolve null se o novo horário não é anterior ao do item.
 */
function applyDnd(fireAt: Date, itemAt: Date, s: ReminderSettings, timeZone: string): Date | null {
  if (!s.dndEnabled) return fireAt;
  const start = hhmmToMinutes(s.dndStart);
  const end = hhmmToMinutes(s.dndEnd);
  if (start === end) return fireAt;
  const { date, minutes } = localParts(fireAt, timeZone);
  const inside = start < end ? minutes >= start && minutes < end : minutes >= start || minutes < end;
  if (!inside) return fireAt;
  const endDate = start > end && minutes >= start ? addDays(date, 1) : date;
  const moved = zonedTime(endDate, s.dndEnd.slice(0, 5), timeZone);
  return moved.getTime() < itemAt.getTime() ? moved : null;
}

/** Avisos de tarefas e eventos (mesmo algoritmo do app): só os que ainda vão soar depois de `now`. */
export function reminderFires(items: ReminderItems, settings: ReminderSettings, now: Date, timeZone: string): ReminderFire[] {
  const candidates: ReminderFire[] = [];
  for (const t of items.tasks) {
    if (t.status === 'done' || !t.dueAt) continue;
    if (localParts(t.dueAt, timeZone).minutes === DATE_ONLY_MINUTES) {
      if (t.priority !== 'alta') continue;
      const fireAt = zonedTime(localParts(t.dueAt, timeZone).date, DATE_ONLY_HOUR, timeZone);
      candidates.push({ kind: 'task', itemId: t.id, title: t.title, fireAt, itemAt: t.dueAt, dateOnly: true });
      continue;
    }
    for (const m of t.reminders) {
      candidates.push({ kind: 'task', itemId: t.id, title: t.title, fireAt: new Date(t.dueAt.getTime() - m * 60_000), itemAt: t.dueAt, dateOnly: false });
    }
  }
  for (const e of items.events) {
    if (e.allDay) continue;
    for (const m of e.reminders) {
      candidates.push({ kind: 'event', itemId: e.id, title: e.title, fireAt: new Date(e.startsAt.getTime() - m * 60_000), itemAt: e.startsAt, dateOnly: false });
    }
  }
  const seen = new Set<string>();
  const out: ReminderFire[] = [];
  for (const c of candidates) {
    const fireAt = applyDnd(c.fireAt, c.itemAt, settings, timeZone);
    if (!fireAt || fireAt.getTime() <= now.getTime()) continue;
    const key = `${c.kind}:${c.itemId}:${fireAt.getTime()}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({ ...c, fireAt });
  }
  return out.sort((a, b) => a.fireAt.getTime() - b.fireAt.getTime());
}

const clean = (s: string) => s.trim().replace(/[.!?;:]+$/, '');

/** "às 15 horas", "às 15 e 30", "à 1 hora", "ao meio-dia", "à meia-noite e 30". */
function spokenClock(minutesOfDay: number): string {
  const h = Math.floor(minutesOfDay / 60);
  const m = minutesOfDay % 60;
  const mins = m ? ` e ${m}` : '';
  if (h === 0) return `à meia-noite${mins}`;
  if (h === 12) return `ao meio-dia${mins}`;
  const art = h === 1 ? 'à' : 'às';
  if (m) return `${art} ${h}${mins}`;
  return `${art} ${h} ${h === 1 ? 'hora' : 'horas'}`;
}

/** Texto falado do aviso. */
export function reminderSpeech(f: ReminderFire, timeZone: string): string {
  const title = clean(f.title);
  const item = localParts(f.itemAt, timeZone);
  const later = item.date !== localParts(f.fireAt, timeZone).date;
  if (f.kind === 'event') {
    return `Lembrete: ${later ? 'amanhã, ' : ''}${title} ${spokenClock(item.minutes)}.`;
  }
  if (f.dateOnly) return `Lembrete: ${later ? 'amanhã' : 'hoje'} vence a tarefa ${title}.`;
  return `Lembrete: a tarefa ${title} vence ${later ? 'amanhã ' : ''}${spokenClock(item.minutes)}.`;
}

/** Atraso máximo tolerado para ainda falar um aviso (a ponte pode ter ficado fora do ar). */
export const REMINDER_LATE_MS = 5 * 60_000;

export interface ReminderData {
  tasks: ReminderTask[];
  events: ReminderEvent[];
  settings: ReminderSettings & { remindersAlexa: boolean; reminderEcho: string | null };
}

export interface ReminderDeps {
  gateway: AlexaGateway;
  timeZone: string;
  now: () => Date;
  log: (msg: string) => void;
  load: (now: Date) => Promise<ReminderData>;
  /** Estado de presença; só `away` bloqueia (dúvida ou erro: fala). */
  presence: () => Promise<PresenceState>;
  /** Registra o envio; false quando já havia registro (outra execução já falou). */
  claim: (f: ReminderFire) => Promise<boolean>;
}

/** Um ciclo do laço: fala no Echo os avisos devidos (janela de 5 min) e devolve quantos falou. */
export async function runReminders(deps: ReminderDeps): Promise<number> {
  const now = deps.now();
  const data = await deps.load(now);
  const { settings } = data;
  if (!settings.remindersAlexa || !settings.reminderEcho) return 0;
  const echo = settings.reminderEcho;
  const due = reminderFires(data, settings, new Date(now.getTime() - REMINDER_LATE_MS), deps.timeZone)
    .filter((f) => f.fireAt.getTime() <= now.getTime());
  if (due.length === 0) return 0;
  try {
    if ((await deps.presence()) === 'away') return 0;
  } catch (e) {
    deps.log(`presença indisponível; lembrando mesmo assim: ${(e as Error).message}`);
  }
  let spoken = 0;
  for (const f of due) {
    try {
      if (!(await deps.claim(f))) continue;
      for (const chunk of chunkSpeech(reminderSpeech(f, deps.timeZone))) await deps.gateway.speak(echo, chunk);
      spoken++;
    } catch (e) {
      if (e instanceof AlexaAuthError) throw e;
      deps.log(`lembrete ${f.kind} falhou: ${(e as Error).message}`);
    }
  }
  return spoken;
}
