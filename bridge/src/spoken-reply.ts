import type { SpokenDate, SpokenTime } from './spoken-date.js';

const WEEKDAYS = ['domingo', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado'];
const MONTHS = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];

const weekdayOf = (x: SpokenDate) => new Date(Date.UTC(x.y, x.m - 1, x.d)).getUTCDay();
const hm = (t: SpokenTime) => (t.min === 0 ? `${t.h}h` : `${t.h}h${String(t.min).padStart(2, '0')}`);

/** "às 15h", "à 1h", "ao meio-dia", "à meia-noite". */
function atTime(t: SpokenTime): string {
  if (t.min === 0 && t.h === 12) return 'ao meio-dia';
  if (t.min === 0 && t.h === 0) return 'à meia-noite';
  return `${t.h === 1 ? 'à' : 'às'} ${hm(t)}`;
}

/** "das 15h", "da 1h", "do meio-dia", "da meia-noite". */
function fromTime(t: SpokenTime): string {
  if (t.min === 0 && t.h === 12) return 'do meio-dia';
  if (t.min === 0 && t.h === 0) return 'da meia-noite';
  return `${t.h === 1 ? 'da' : 'das'} ${hm(t)}`;
}

/** Dia falado: "hoje", "amanhã, quarta", "depois de amanhã, quinta" ou, mais longe, "sexta, 24 de outubro". */
function dayText(date: SpokenDate, today: SpokenDate, withArticle: boolean): string {
  const dow = WEEKDAYS[weekdayOf(date)];
  const days = Math.round((Date.UTC(date.y, date.m - 1, date.d) - Date.UTC(today.y, today.m - 1, today.d)) / 86_400_000);
  if (days === 0) return 'hoje';
  if (days === 1) return `amanhã, ${dow}`;
  if (days === 2) return `depois de amanhã, ${dow}`;
  const year = date.y === today.y ? '' : ` de ${date.y}`;
  const article = !withArticle ? '' : weekdayOf(date) === 0 || weekdayOf(date) === 6 ? 'no ' : 'na ';
  return `${article}${dow}, ${date.d} de ${MONTHS[date.m - 1]}${year}`;
}

/** "Anotei a tarefa estudar cálculo para sexta, 24 de outubro." / sem prazo: "Anotei a tarefa estudar cálculo." */
export function taskAddedText(title: string, date: SpokenDate | null, time: SpokenTime | null, today: SpokenDate): string {
  if (!date) return `Anotei a tarefa ${title}.`;
  const at = time ? `, ${atTime(time)}` : '';
  return `Anotei a tarefa ${title} para ${dayText(date, today, false)}${at}.`;
}

/** "Marquei reunião amanhã, quarta, das 15h às 16h." / dia inteiro: "Marquei feriado na sexta, 24 de outubro, o dia todo." */
export function eventAddedText(title: string, date: SpokenDate, time: SpokenTime | null, today: SpokenDate): string {
  const day = dayText(date, today, true);
  if (!time) return `Marquei ${title} ${day}, o dia todo.`;
  const end: SpokenTime = { h: (time.h + 1) % 24, min: time.min };
  return `Marquei ${title} ${day}, ${fromTime(time)} ${atTime(end)}.`;
}

