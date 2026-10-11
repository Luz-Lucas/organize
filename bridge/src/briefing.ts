import { formatLongDate, formatTime, localParts } from './time.js';

export interface BriefingEvent { title: string; startsAt: Date; endsAt: Date; allDay: boolean; location: string | null }
export interface BriefingTask { title: string }
export interface BriefingNews { title: string; source: string }
export interface BriefingInput {
  now: Date;
  timeZone: string;
  events: BriefingEvent[];
  overdue: BriefingTask[];
  dueToday: BriefingTask[];
  news: BriefingNews[];
}

const MAX_EVENTS = 6;
const MAX_TASKS = 5;

const clean = (s: string) => s.trim().replace(/[.!?;:]+$/, '');

function joinList(items: string[]): string {
  if (items.length <= 1) return items.join('');
  return `${items.slice(0, -1).join(', ')} e ${items[items.length - 1]}`;
}

function taskList(tasks: BriefingTask[]): string {
  const shown = joinList(tasks.slice(0, MAX_TASKS).map((t) => clean(t.title)));
  return tasks.length > MAX_TASKS ? `${shown}, e mais ${tasks.length - MAX_TASKS}` : shown;
}

function greeting(now: Date, timeZone: string): string {
  const minutes = localParts(now, timeZone).minutes;
  return minutes < 12 * 60 ? 'Bom dia' : minutes < 18 * 60 ? 'Boa tarde' : 'Boa noite';
}

export function headlinesText(news: BriefingNews[]): string {
  if (news.length === 0) return 'Não encontrei manchetes das suas fontes agora.';
  return `Manchetes: ${news.map((n) => `${n.source}: ${clean(n.title)}`).join('. ')}.`;
}

export function buildBriefing(i: BriefingInput): string {
  const parts = [`${greeting(i.now, i.timeZone)}! Hoje é ${formatLongDate(i.now, i.timeZone)}.`];

  if (i.events.length === 0) {
    parts.push('Sua agenda de hoje está livre.');
  } else {
    const shown = i.events.slice(0, MAX_EVENTS).map((e) => {
      const when = e.allDay ? 'o dia todo' : `às ${formatTime(e.startsAt, i.timeZone)}`;
      return `${when}, ${clean(e.title)}${e.location ? `, em ${clean(e.location)}` : ''}`;
    });
    const n = i.events.length;
    const more = n > MAX_EVENTS ? `; e mais ${n - MAX_EVENTS}` : '';
    parts.push(`Você tem ${n === 1 ? '1 compromisso' : `${n} compromissos`}: ${shown.join('; ')}${more}.`);
  }

  parts.push(i.dueToday.length ? `Para hoje: ${taskList(i.dueToday)}.` : 'Nenhuma tarefa com prazo para hoje.');

  if (i.overdue.length) {
    const count = i.overdue.length === 1 ? 'há 1 tarefa atrasada' : `há ${i.overdue.length} tarefas atrasadas`;
    parts.push(`Atenção, ${count}: ${taskList(i.overdue)}.`);
  }

  if (i.news.length) parts.push(headlinesText(i.news));
  return parts.join(' ');
}

/** Os dois textos que o despertar pode falar: o resumo completo e só as manchetes. */
export function wakeTexts(i: BriefingInput): { briefing: string; headlines: string } {
  return { briefing: buildBriefing(i), headlines: headlinesText(i.news) };
}

export function splitTasks(
  tasks: { title: string; dueAt: Date }[],
  dayStart: Date,
): { overdue: BriefingTask[]; dueToday: BriefingTask[] } {
  const overdue: BriefingTask[] = [];
  const dueToday: BriefingTask[] = [];
  for (const t of tasks) (t.dueAt < dayStart ? overdue : dueToday).push({ title: t.title });
  return { overdue, dueToday };
}

export function chunkSpeech(text: string, max = 240): string[] {
  const words = text.replace(/\s+/g, ' ').trim().split(' ');
  const chunks: string[] = [];
  let current = '';
  for (const word of words) {
    const candidate = current ? `${current} ${word}` : word;
    const sentenceBreak = /[.!?;]$/.test(current) && candidate.length > max * 0.6;
    if (candidate.length > max || sentenceBreak) {
      if (current) chunks.push(current);
      current = word.slice(0, max);
    } else {
      current = candidate;
    }
  }
  if (current) chunks.push(current);
  return chunks;
}

export function escapeSsml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}
