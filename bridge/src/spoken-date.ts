import { addDays, localParts, zonedTime } from './time.js';

export interface SpokenDate { y: number; m: number; d: number }
export interface SpokenTime { h: number; min: number }
export interface SpokenRequest { title: string; date: SpokenDate | null; time: SpokenTime | null }

/** Remove acentos e caixa. Em texto NFC, o resultado tem o mesmo tamanho (cortamos o original pelo índice). */
function fold(s: string): string {
  return s.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase();
}

const MONTHS = ['janeiro', 'fevereiro', 'marco', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];
const MONTH_RE = MONTHS.join('|');
// getUTCDay(): domingo = 0
const WEEKDAYS: Record<string, number> = { domingo: 0, segunda: 1, terca: 2, quarta: 3, quinta: 4, sexta: 5, sabado: 6 };

const HOUR_WORDS: Record<string, number> = {
  zero: 0, um: 1, uma: 1, dois: 2, duas: 2, tres: 3, quatro: 4, cinco: 5, seis: 6, sete: 7, oito: 8, nove: 9, dez: 10,
  onze: 11, doze: 12, treze: 13, catorze: 14, quatorze: 14, quinze: 15, dezesseis: 16, dezessete: 17, dezoito: 18,
  dezenove: 19, vinte: 20, 'vinte e um': 21, 'vinte e uma': 21, 'vinte e dois': 22, 'vinte e duas': 22, 'vinte e tres': 23,
};
const MINUTE_WORDS: Record<string, number> = {
  meia: 30, quinze: 15, vinte: 20, trinta: 30, quarenta: 40, 'quarenta e cinco': 45, cinquenta: 50,
};
const longestFirst = (words: string[]) => [...words].sort((a, b) => b.length - a.length).join('|');
const HOUR_RE = `\\d{1,2}|${longestFirst(Object.keys(HOUR_WORDS))}`;
const MINUTE_RE = `[0-5]\\d|${longestFirst(Object.keys(MINUTE_WORDS))}`;

const TIME_RE = new RegExp(
  `(?<![a-z0-9:])(?:(as)\\s+)?(${HOUR_RE})` +
  `(?::([0-5]\\d)|\\s?(h)(?:oras?|s)?(?![a-z])(?:([0-5]\\d)|\\s+e\\s+(${MINUTE_RE}))?|\\s+(e)\\s+(${MINUTE_RE}))?` +
  `(?:\\s+(?:da|de|na|pela)\\s+(manha|tarde|noite|madrugada))?(?![a-z0-9])`,
  'g',
);
const NOON_RE = /(?<![a-z])(meio[- ]?dia|meia[- ]?noite)(?![a-z])/g;

// Palavras de ligação que sobram ao lado do trecho de data/hora removido.
const PREPS = ['para', 'pra', 'pro', 'no', 'na', 'nos', 'nas', 'em', 'as', 'de', 'do', 'da', 'ao', 'ate', 'por', 'pelo', 'pela', 'das', 'dos'];
const ARTICLES = ['a', 'o', 'os', 'um', 'uma'];
const LEFT_RE = new RegExp(`(?:(?<![a-z0-9])(?:${[...PREPS, ...ARTICLES].join('|')})\\s+)+$`);

interface Span { from: number; to: number }

const num = (s: string): number => (/^\d+$/.test(s) ? Number(s) : HOUR_WORDS[s]);
const validYmd = (y: number, m: number, d: number) => {
  const t = new Date(Date.UTC(y, m - 1, d));
  return t.getUTCFullYear() === y && t.getUTCMonth() === m - 1 && t.getUTCDate() === d;
};
const key = (x: SpokenDate) => x.y * 10000 + x.m * 100 + x.d;

/** Próxima ocorrência (hoje conta) de dia/mês, no ano seguinte se já passou. */
function nextMonthDay(d: number, m: number, today: SpokenDate): SpokenDate | null {
  for (let y = today.y; y <= today.y + 8; y++) {
    if (validYmd(y, m, d) && key({ y, m, d }) >= key(today)) return { y, m, d };
  }
  return null;
}

/** "dia 25": neste mês se ainda não passou (hoje conta); senão no próximo mês que tenha esse dia. */
function nextDayOfMonth(d: number, today: SpokenDate): SpokenDate | null {
  for (let i = 0; i < 14; i++) {
    const idx = today.m - 1 + i;
    const y = today.y + Math.floor(idx / 12);
    const m = (idx % 12) + 1;
    if (validYmd(y, m, d) && key({ y, m, d }) >= key(today)) return { y, m, d };
  }
  return null;
}

const fromIso = (iso: string): SpokenDate => {
  const [y, m, d] = iso.split('-').map(Number);
  return { y, m, d };
};
const toIso = (x: SpokenDate) => `${x.y}-${String(x.m).padStart(2, '0')}-${String(x.d).padStart(2, '0')}`;

interface Found<T> extends Span { value: T }

function findDate(f: string, today: SpokenDate): Found<SpokenDate> | null {
  const todayIso = toIso(today);
  const rel = (n: number) => fromIso(addDays(todayIso, n));
  const simple: [RegExp, number][] = [
    [/(?<![a-z])depois de amanha(?![a-z])/, 2],
    [/(?<![a-z])amanha(?![a-z])/, 1],
    [/(?<![a-z])hoje(?![a-z])/, 0],
  ];
  for (const [re, n] of simple) {
    const m = re.exec(f);
    if (m) return { from: m.index, to: m.index + m[0].length, value: rel(n) };
  }

  const patterns: { re: RegExp; resolve: (m: RegExpExecArray) => SpokenDate | null }[] = [
    {
      re: new RegExp(`(?<![a-z0-9])(?:dia\\s+)?(\\d{1,2})\\s+de\\s+(${MONTH_RE})(?:\\s+de\\s+(\\d{4}))?(?![a-z0-9])`, 'g'),
      resolve: (m) => {
        const d = Number(m[1]);
        const mo = MONTHS.indexOf(m[2]) + 1;
        if (m[3]) return validYmd(Number(m[3]), mo, d) ? { y: Number(m[3]), m: mo, d } : null;
        return nextMonthDay(d, mo, today);
      },
    },
    {
      re: /(?<![a-z0-9\/])(?:dia\s+)?(\d{1,2})\/(\d{1,2})(?![a-z0-9\/])/g,
      resolve: (m) => (Number(m[2]) >= 1 && Number(m[2]) <= 12 ? nextMonthDay(Number(m[1]), Number(m[2]), today) : null),
    },
    {
      re: new RegExp(`(?<![a-z])dia\\s+(\\d{1,2})(?![a-z0-9\\/])(?!\\s+de\\s+(?:${MONTH_RE})(?![a-z]))`, 'g'),
      resolve: (m) => nextDayOfMonth(Number(m[1]), today),
    },
    {
      re: new RegExp(`(?<![a-z])(?:(?:nesta|esta|essa|nessa|proxima|proximo)\\s+)?(${Object.keys(WEEKDAYS).join('|')})(?:[- ]feira)?(?:\\s+que\\s+vem)?(?![a-z])`, 'g'),
      resolve: (m) => {
        const dow = new Date(Date.UTC(today.y, today.m - 1, today.d)).getUTCDay();
        return rel(((WEEKDAYS[m[1]] - dow + 7) % 7) || 7); // próxima ocorrência, nunca hoje
      },
    },
  ];
  for (const { re, resolve } of patterns) {
    for (const m of f.matchAll(re)) {
      const value = resolve(m);
      if (value) return { from: m.index, to: m.index + m[0].length, value };
    }
  }
  return null;
}

function applyPeriod(h: number, period: string | undefined): number {
  if (period === 'tarde') return h < 12 ? h + 12 : h;
  if (period === 'noite') return h < 12 ? h + 12 : h === 12 ? 0 : h;
  if (period === 'madrugada') return h === 12 ? 0 : h;
  return h;
}

function findTime(f: string): Found<SpokenTime> | null {
  for (const m of f.matchAll(TIME_RE)) {
    const [, as, hourTxt, colonMin, hMark, hMin, hWordMin, eMark, eMin, period] = m;
    const minTxt = colonMin ?? hMin ?? hWordMin ?? eMin;
    const min = minTxt === undefined ? 0 : /^\d+$/.test(minTxt) ? Number(minTxt) : MINUTE_WORDS[minTxt];
    // Número solto ("capítulo 3", "2 livros") não é hora: precisa de marca de hora, "às", período ou "H e MM".
    const marked = colonMin !== undefined || hMark !== undefined || as !== undefined || period !== undefined
      || (eMark !== undefined && /^\d/.test(eMin));
    const hour = num(hourTxt);
    if (!marked || hour > 23 || min > 59) continue;
    const h = applyPeriod(hour, period);
    return { from: m.index, to: m.index + m[0].length, value: { h, min } };
  }
  const noon = NOON_RE.exec(f);
  NOON_RE.lastIndex = 0;
  if (noon) return { from: noon.index, to: noon.index + noon[0].length, value: { h: noon[1].startsWith('meio') ? 12 : 0, min: 0 } };
  return null;
}

/** Estende o trecho para a esquerda por "para", "no", "às", "o"… coladas nele. */
function extendLeft(f: string, span: Span): Span {
  const m = LEFT_RE.exec(f.slice(0, span.from));
  return m ? { from: span.from - m[0].length, to: span.to } : span;
}

const mask = (s: string, { from, to }: Span) => s.slice(0, from) + ' '.repeat(to - from) + s.slice(to);

const EDGE_PREPS = new Set([...PREPS, 'dia']);
const TRAIL = new Set([...EDGE_PREPS, ...ARTICLES, 'e']);

function cleanTitle(raw: string): string {
  const words = raw.replace(/[.!?;:,\s]+$/, '').split(/\s+/).filter(Boolean);
  let strippedPrep = false;
  while (words.length) {
    const w = fold(words[0]);
    if (EDGE_PREPS.has(w)) strippedPrep = true;
    else if (!(strippedPrep && ARTICLES.includes(w))) break;
    words.shift();
  }
  while (words.length && TRAIL.has(fold(words[words.length - 1]))) words.pop();
  return words.join(' ').replace(/[.!?;:,\s]+$/, '').trim();
}

/**
 * Entende um pedido falado em pt-BR ("reunião com o Pedro amanhã às 15h"): separa o título da data e da hora.
 * Dias da semana valem para a próxima ocorrência (nunca hoje); "dia 25" e "25 de novembro" vão para o próximo
 * que ainda não passou. `now` e `timeZone` definem o "hoje" local. Título vazio = não deu para entender.
 */
export function parseSpokenRequest(text: string, now: Date, timeZone: string): SpokenRequest {
  const original = text.normalize('NFC');
  let f = fold(original);
  let masked = original;
  const today = fromIso(localParts(now, timeZone).date);

  const date = findDate(f, today);
  if (date) {
    const span = extendLeft(f, date);
    f = mask(f, span);
    masked = mask(masked, span);
  }
  const time = findTime(f);
  if (time) {
    const span = extendLeft(f, time);
    masked = mask(masked, span);
  }
  return { title: cleanTitle(masked), date: date?.value ?? null, time: time?.value ?? null };
}

const hhmm = (t: SpokenTime) => `${String(t.h).padStart(2, '0')}:${String(t.min).padStart(2, '0')}`;

/** Prazo da tarefa: com hora, essa hora local; só data, até 23:59 do dia (igual ao create_task do MCP). */
export function taskDue(date: SpokenDate, time: SpokenTime | null, timeZone: string): Date {
  return zonedTime(toIso(date), time ? hhmm(time) : '23:59', timeZone);
}
