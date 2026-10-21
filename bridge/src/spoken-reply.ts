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

/** Dia falado: "hoje", "amanhã, quarta, 21 de outubro", "depois de amanhã, quinta, 22 de outubro" ou, mais longe, "sexta, 24 de outubro". */
function dayText(date: SpokenDate, today: SpokenDate): string {
  const dow = WEEKDAYS[weekdayOf(date)];
  const days = Math.round((Date.UTC(date.y, date.m - 1, date.d) - Date.UTC(today.y, today.m - 1, today.d)) / 86_400_000);
  if (days === 0) return 'hoje';
  const year = date.y === today.y ? '' : ` de ${date.y}`;
  const full = `${dow}, ${date.d} de ${MONTHS[date.m - 1]}${year}`;
  if (days === 1) return `amanhã, ${full}`;
  if (days === 2) return `depois de amanhã, ${full}`;
  return full;
}

/** "Anotei a tarefa estudar cálculo para sexta, 24 de outubro." / sem prazo: "Anotei a tarefa estudar cálculo." */
export function taskAddedText(title: string, date: SpokenDate | null, time: SpokenTime | null, today: SpokenDate): string {
  if (!date) return `Anotei a tarefa ${title}.`;
  const at = time ? `, ${atTime(time)}` : '';
  return `Anotei a tarefa ${title} para ${dayText(date, today)}${at}.`;
}
