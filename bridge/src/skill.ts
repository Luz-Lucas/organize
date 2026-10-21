import askCore from 'ask-sdk-core';
import type { ErrorHandler, HandlerInput, RequestHandler, Skill } from 'ask-sdk-core';
import type { Intent } from 'ask-sdk-model';
import { escapeSsml } from './briefing.js';
import { parseSpokenRequest, taskDue, type SpokenDate } from './spoken-date.js';
import { taskAddedText } from './spoken-reply.js';
import { localParts } from './time.js';

const { SkillBuilders, getRequestType, getIntentName, getUserId, getSlotValue } = askCore;

export interface SkillDeps {
  allowedUserId: string | null;
  log: (m: string) => void;
  /** Fuso da ponte: define o "hoje" e as horas faladas. */
  timeZone: string;
  /** Relógio (os testes fixam). */
  now?: () => Date;
  /** Cria uma tarefa (`dueAt` null = sem prazo). */
  addTask: (task: { title: string; dueAt: Date | null; priority: 'baixa' | 'media' | 'alta' }) => Promise<void>;
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
  const now = () => (deps.now ?? (() => new Date()))();
  const todayOf = (at: Date): SpokenDate => {
    const [y, m, d] = localParts(at, deps.timeZone).date.split('-').map(Number);
    return { y, m, d };
  };
  /**
   * Pergunta a tarefa mantendo a sessão aberta: `Dialog.ElicitSlot` com o intent de tarefa faz a próxima fala
   * (sem frase de abertura) preencher o campo `pedido`.
   */
  const askTask = (h: HandlerInput, speech = 'Qual é a tarefa?') => {
    const intent: Intent = { name: 'AdicionarTarefaIntent', confirmationStatus: 'NONE', slots: { pedido: { name: 'pedido', confirmationStatus: 'NONE' } } };
    return h.responseBuilder
      .speak(escapeSsml(speech))
      .reprompt('Qual é a tarefa?')
      .addElicitSlotDirective('pedido', intent)
      .getResponse();
  };
  const launch: RequestHandler = {
    canHandle: (h) => isType(h, 'LaunchRequest') || isIntent(h, 'AMAZON.FallbackIntent'),
    handle: (h) => askTask(h),
  };

  const addTask: RequestHandler = {
    canHandle: (h) => isIntent(h, 'AdicionarTarefaIntent'),
    handle: async (h) => {
      const at = now();
      const parsed = parseSpokenRequest(getSlotValue(h.requestEnvelope, 'pedido') ?? '', at, deps.timeZone);
      const { title, time } = parsed;
      if (!title) return askTask(h);
      const date = parsed.date ?? (time ? todayOf(at) : null); // "às 17h" sem dia vale para hoje
      try {
        await deps.addTask({ title, dueAt: date ? taskDue(date, time, deps.timeZone) : null, priority: 'alta' });
      } catch (e) {
        deps.log(`erro ao criar tarefa: ${(e as Error).message}`);
        return say(h, 'Não consegui anotar a tarefa agora. Tente de novo em instantes.');
      }
      return say(h, taskAddedText(title, date, time, todayOf(at)));
    },
  };
  const help: RequestHandler = {
    canHandle: (h) => isIntent(h, 'AMAZON.HelpIntent'),
    handle: (h) => askTask(h, 'Diga a tarefa, por exemplo: adicionar estudar cálculo para sexta.'),
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
      return say(h, 'Não consegui anotar a tarefa agora. Tente de novo em instantes.');
    },
  };

  return SkillBuilders.custom()
    .addRequestHandlers(guard, launch, addTask, help, stop, ended)
    .addErrorHandlers(errors)
    .create();
}
