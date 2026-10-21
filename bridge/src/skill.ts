import askCore from 'ask-sdk-core';
import type { ErrorHandler, HandlerInput, RequestHandler, Skill } from 'ask-sdk-core';
import type { IntentRequest } from 'ask-sdk-model';
import { buildBriefing, escapeSsml, headlinesText, type BriefingInput } from './briefing.js';
import { eventRange, parseSpokenRequest, taskDue, type SpokenDate } from './spoken-date.js';
import { eventAddedText, taskAddedText } from './spoken-reply.js';
import { localParts } from './time.js';

const { SkillBuilders, getRequestType, getIntentName, getUserId, getSlotValue } = askCore;

export interface SkillDeps {
  allowedUserId: string | null;
  briefingInput: () => Promise<BriefingInput>;
  log: (m: string) => void;
  /** Fuso da ponte: define o "hoje" e as horas faladas. */
  timeZone: string;
  /** Relógio (os testes fixam). */
  now?: () => Date;
  /** Cria uma tarefa (`dueAt` null = sem prazo). */
  addTask: (task: { title: string; dueAt: Date | null }) => Promise<void>;
  /** Cria um evento (dia inteiro: início e fim à meia-noite local). */
  addEvent: (event: { title: string; startsAt: Date; endsAt: Date; allDay: boolean }) => Promise<void>;
}

export function buildSkill(deps: SkillDeps): Skill {
  const say = (h: HandlerInput, text: string) =>
    h.responseBuilder.speak(escapeSsml(text)).withShouldEndSession(true).getResponse();
  const isType = (h: HandlerInput, type: string) => getRequestType(h.requestEnvelope) === type;
  const isIntent = (h: HandlerInput, ...names: string[]) =>
    isType(h, 'IntentRequest') && names.includes(getIntentName(h.requestEnvelope));

  const guard: RequestHandler = {
    canHandle: (h) => deps.allowedUserId === null || getUserId(h.requestEnvelope) !== deps.allowedUserId,
    handle: (h) => {
      deps.log(`skill chamada pela conta ${getUserId(h.requestEnvelope)}`);
      return say(h, deps.allowedUserId === null
        ? 'Skill ainda não configurada. Veja no log da ponte o identificador desta conta.'
        : 'Esta skill é privada.');
    },
  };
  const briefing: RequestHandler = {
    canHandle: (h) => isType(h, 'LaunchRequest') || isIntent(h, 'ResumoDoDiaIntent'),
    handle: async (h) => say(h, buildBriefing(await deps.briefingInput())),
  };
  const news: RequestHandler = {
    canHandle: (h) => isIntent(h, 'NoticiasIntent'),
    handle: async (h) => say(h, headlinesText((await deps.briefingInput()).news)),
  };
  const now = () => (deps.now ?? (() => new Date()))();
  const todayOf = (at: Date): SpokenDate => {
    const [y, m, d] = localParts(at, deps.timeZone).date.split('-').map(Number);
    return { y, m, d };
  };
  /** Pergunta de novo mantendo a sessão: a próxima fala preenche o campo `pedido` do mesmo intent. */
  const askAgain = (h: HandlerInput, question: string) =>
    h.responseBuilder
      .speak(question)
      .reprompt(question)
      .addElicitSlotDirective('pedido', (h.requestEnvelope.request as IntentRequest).intent)
      .getResponse();

  const addTask: RequestHandler = {
    canHandle: (h) => isIntent(h, 'AdicionarTarefaIntent'),
    handle: async (h) => {
      const at = now();
      const parsed = parseSpokenRequest(getSlotValue(h.requestEnvelope, 'pedido') ?? '', at, deps.timeZone);
      const { title, time } = parsed;
      if (!title) return askAgain(h, 'Qual é a tarefa?');
      const date = parsed.date ?? (time ? todayOf(at) : null); // "às 17h" sem dia vale para hoje
      try {
        await deps.addTask({ title, dueAt: date ? taskDue(date, time, deps.timeZone) : null });
      } catch (e) {
        deps.log(`erro ao criar tarefa: ${(e as Error).message}`);
        return say(h, 'Não consegui anotar a tarefa agora. Tente de novo em instantes.');
      }
      return say(h, taskAddedText(title, date, time, todayOf(at)));
    },
  };
  const addEvent: RequestHandler = {
    canHandle: (h) => isIntent(h, 'CriarEventoIntent'),
    handle: async (h) => {
      const at = now();
      const today = todayOf(at);
      const parsed = parseSpokenRequest(getSlotValue(h.requestEnvelope, 'pedido') ?? '', at, deps.timeZone);
      if (!parsed.title) return askAgain(h, 'O que você quer marcar?');
      const date = parsed.date ?? today;
      try {
        await deps.addEvent({ title: parsed.title, ...eventRange(date, parsed.time, deps.timeZone) });
      } catch (e) {
        deps.log(`erro ao criar evento: ${(e as Error).message}`);
        return say(h, 'Não consegui marcar o evento agora. Tente de novo em instantes.');
      }
      return say(h, eventAddedText(parsed.title, date, parsed.time, today));
    },
  };
  const help: RequestHandler = {
    canHandle: (h) => isIntent(h, 'AMAZON.HelpIntent', 'AMAZON.FallbackIntent'),
    handle: (h) =>
      h.responseBuilder
        .speak('Você pode dizer: qual é o meu dia; adicionar tarefa estudar para sexta; ou marcar reunião amanhã às 15h.')
        .reprompt('O que você quer saber?')
        .getResponse(),
  };
  const stop: RequestHandler = {
    canHandle: (h) => isIntent(h, 'AMAZON.StopIntent', 'AMAZON.CancelIntent', 'AMAZON.NavigateHomeIntent'),
    handle: (h) => say(h, 'Até mais!'),
  };
  const ended: RequestHandler = {
    canHandle: (h) => isType(h, 'SessionEndedRequest'),
    handle: (h) => h.responseBuilder.getResponse(),
  };
  const errors: ErrorHandler = {
    canHandle: () => true,
    handle: (h, error) => {
      deps.log(`erro na skill: ${error.message}`);
      return say(h, 'Não consegui acessar sua agenda agora. Tente de novo em instantes.');
    },
  };

  return SkillBuilders.custom()
    .addRequestHandlers(guard, briefing, news, addTask, addEvent, help, stop, ended)
    .addErrorHandlers(errors)
    .create();
}
