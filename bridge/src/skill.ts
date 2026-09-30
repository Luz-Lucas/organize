import askCore from 'ask-sdk-core';
import type { ErrorHandler, HandlerInput, RequestHandler, Skill } from 'ask-sdk-core';
import { buildBriefing, escapeSsml, headlinesText, type BriefingInput } from './briefing.js';

const { SkillBuilders, getRequestType, getIntentName, getUserId } = askCore;

export interface SkillDeps {
  allowedUserId: string | null;
  briefingInput: () => Promise<BriefingInput>;
  log: (m: string) => void;
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
  const help: RequestHandler = {
    canHandle: (h) => isIntent(h, 'AMAZON.HelpIntent', 'AMAZON.FallbackIntent'),
    handle: (h) =>
      h.responseBuilder
        .speak('Você pode dizer: qual é o meu dia. Ou: quais são as notícias.')
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
    .addRequestHandlers(guard, briefing, news, help, stop, ended)
    .addErrorHandlers(errors)
    .create();
}
