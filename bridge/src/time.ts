const partsFormatter = new Map<string, Intl.DateTimeFormat>();

function formatterFor(timeZone: string): Intl.DateTimeFormat {
  let f = partsFormatter.get(timeZone);
  if (!f) {
    f = new Intl.DateTimeFormat('en-US', {
      timeZone, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', second: '2-digit',
    });
    partsFormatter.set(timeZone, f);
  }
  return f;
}

export function tzOffsetMinutes(at: Date, timeZone: string): number {
  const parts = formatterFor(timeZone).formatToParts(at);
  const get = (type: string) => Number(parts.find((p) => p.type === type)!.value);
  const asUtc = Date.UTC(get('year'), get('month') - 1, get('day'), get('hour'), get('minute'), get('second'));
  return Math.round((asUtc - Math.floor(at.getTime() / 1000) * 1000) / 60000);
}

export function localParts(at: Date, timeZone: string): { date: string; weekday: number; minutes: number } {
  const local = new Date(at.getTime() + tzOffsetMinutes(at, timeZone) * 60000);
  return {
    date: local.toISOString().slice(0, 10),
    weekday: ((local.getUTCDay() + 6) % 7) + 1,
    minutes: local.getUTCHours() * 60 + local.getUTCMinutes(),
  };
}

export function zonedTime(date: string, hhmm: string, timeZone: string): Date {
  const [y, m, d] = date.split('-').map(Number);
  const [h, mi] = hhmm.split(':').map(Number);
  const guess = Date.UTC(y, m - 1, d, h, mi);
  const first = guess - tzOffsetMinutes(new Date(guess), timeZone) * 60000;
  return new Date(guess - tzOffsetMinutes(new Date(first), timeZone) * 60000);
}

export function addDays(date: string, n: number): string {
  const [y, m, d] = date.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}

export function zonedDayRange(now: Date, timeZone: string): { start: Date; end: Date } {
  const today = localParts(now, timeZone).date;
  return { start: zonedTime(today, '00:00', timeZone), end: zonedTime(addDays(today, 1), '00:00', timeZone) };
}

export function formatLongDate(at: Date, timeZone: string): string {
  return new Intl.DateTimeFormat('pt-BR', { timeZone, weekday: 'long', day: 'numeric', month: 'long' }).format(at);
}

export function formatTime(at: Date, timeZone: string): string {
  return new Intl.DateTimeFormat('pt-BR', { timeZone, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(at);
}

export function timeZoneMatches(
  now: Date,
  timeZone: string,
  processOffsetMinutes: number = -now.getTimezoneOffset(),
): boolean {
  return tzOffsetMinutes(now, timeZone) === processOffsetMinutes;
}
