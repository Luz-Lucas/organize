import askCore from 'ask-sdk-core';
import type { ErrorHandler, HandlerInput, RequestHandler, Skill } from 'ask-sdk-core';
import { buildBriefing, escapeSsml, headlinesText, type BriefingInput } from './briefing.js';
import { addedText, listSummaryText, parseShoppingUtterance } from './shopping.js';

const { SkillBuilders, getRequestType, getIntentName, getUserId, getSlotValue } = askCore;

export interface SkillDeps {
  allowedUserId: string | null;
  briefingInput: () => Promise<BriefingInput>;
  log: (m: string) => void;
  /** Põe itens na lista (`null` = padrão, "Mercado"); o que já estava na lista não marcada vem em `skipped`. */
  addShopping: (items: string[], list: string | null) => Promise<{ added: string[]; skipped: string[]; list: string }>;
  /** Listas com os itens ainda não marcados. */
  shoppingSummary: () => Promise<{ list: string; items: string[] }[]>;
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
  const addShopping: RequestHandler = {
    canHandle: (h) => isIntent(h, 'AdicionarCompraIntent'),
    handle: async (h) => {
      const spoken = getSlotValue(h.requestEnvelope, 'item') ?? '';
      try {
        const lists = (await deps.shoppingSummary()).map((l) => l.list);
        const { list, items } = parseShoppingUtterance(spoken, lists);
        if (items.length === 0) {
          return h.responseBuilder.speak('O que você quer adicionar?').reprompt('O que você quer adicionar à lista?').getResponse();
        }
        return say(h, addedText(await deps.addShopping(items, list)));
      } catch (e) {
        deps.log(`erro nas compras: ${(e as Error).message}`);
        return say(h, 'Não consegui acessar sua lista de compras agora. Tente de novo em instantes.');
      }
    },
  };
  const readShopping: RequestHandler = {
    canHandle: (h) => isIntent(h, 'ListaDeComprasIntent'),
    handle: async (h) => {
      try {
        return say(h, listSummaryText(await deps.shoppingSummary()));
      } catch (e) {
        deps.log(`erro nas compras: ${(e as Error).message}`);
        return say(h, 'Não consegui acessar sua lista de compras agora. Tente de novo em instantes.');
      }
    },
  };
  const help: RequestHandler = {
    canHandle: (h) => isIntent(h, 'AMAZON.HelpIntent', 'AMAZON.FallbackIntent'),
    handle: (h) =>
      h.responseBuilder
        .speak('Você pode dizer: qual é o meu dia. Ou: quais são as notícias. Ou: adicionar leite.')
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
    .addRequestHandlers(guard, briefing, news, addShopping, readShopping, help, stop, ended)
    .addErrorHandlers(errors)
    .create();
}
