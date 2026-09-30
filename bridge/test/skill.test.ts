import { describe, expect, it } from 'vitest';
import type { BriefingInput } from '../src/briefing.js';
import { buildSkill } from '../src/skill.js';

const USER = 'amzn1.ask.account.EU';
const input: BriefingInput = {
  now: new Date('2026-09-28T10:00:00Z'),
  timeZone: 'America/Sao_Paulo',
  events: [{ title: 'P&D <Lab>', startsAt: new Date('2026-09-28T11:00:00Z'), endsAt: new Date('2026-09-28T12:00:00Z'), allDay: false, location: null }],
  overdue: [],
  dueToday: [],
  news: [{ source: 'G1', title: 'Chuva forte' }],
};

function envelope(request: Record<string, unknown>, userId = USER) {
  return {
    version: '1.0',
    session: { new: true, sessionId: 's', application: { applicationId: 'app' }, user: { userId } },
    context: { System: { application: { applicationId: 'app' }, user: { userId }, apiEndpoint: 'https://api.amazonalexa.com' } },
    request: { requestId: 'r', timestamp: new Date().toISOString(), locale: 'pt-BR', ...request },
  };
}

const intent = (name: string) => ({ type: 'IntentRequest', intent: { name, confirmationStatus: 'NONE' } });

async function ssml(skill: ReturnType<typeof buildSkill>, request: Record<string, unknown>, userId = USER) {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const res = await skill.invoke(envelope(request, userId) as any);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return (res.response.outputSpeech as any)?.ssml as string;
}

describe('skill', () => {
  const logs: string[] = [];
  const skill = buildSkill({ allowedUserId: USER, briefingInput: async () => input, log: (m) => logs.push(m) });

  it('abrir a skill fala o resumo com SSML escapado', async () => {
    const out = await ssml(skill, { type: 'LaunchRequest' });
    expect(out).toContain('Bom dia! Hoje é segunda-feira, 28 de setembro.');
    expect(out).toContain('P&amp;D &lt;Lab&gt;');
    expect(out).not.toContain('<Lab>');
  });

  it('ResumoDoDiaIntent e NoticiasIntent', async () => {
    expect(await ssml(skill, intent('ResumoDoDiaIntent'))).toContain('Você tem 1 compromisso');
    expect(await ssml(skill, intent('NoticiasIntent'))).toContain('Manchetes: G1: Chuva forte.');
  });

  it('outra conta Amazon recebe recusa', async () => {
    expect(await ssml(skill, { type: 'LaunchRequest' }, 'amzn1.ask.account.OUTRO')).toContain('Esta skill é privada.');
  });

  it('sem ALEXA_ALLOWED_USER_ID configurado, loga o id da conta', async () => {
    const seen: string[] = [];
    const open = buildSkill({ allowedUserId: null, briefingInput: async () => input, log: (m) => seen.push(m) });
    expect(await ssml(open, { type: 'LaunchRequest' })).toContain('ainda não configurada');
    expect(seen.join('\n')).toContain(USER);
  });

  it('erro ao ler a agenda vira mensagem amigável', async () => {
    const broken = buildSkill({ allowedUserId: USER, briefingInput: async () => { throw new Error('db fora'); }, log: () => {} });
    expect(await ssml(broken, { type: 'LaunchRequest' })).toContain('Não consegui acessar sua agenda agora.');
  });

  it('parar se despede', async () => {
    expect(await ssml(skill, intent('AMAZON.StopIntent'))).toContain('Até mais!');
  });
});
