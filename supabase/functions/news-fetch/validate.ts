import { FeedError } from "./feed.ts";

/** Mensagem pt-BR curta para o app; nunca expõe o texto cru do erro. */
export const validateErrorMessage = (e: unknown): string =>
  e instanceof FeedError ? e.message : "não foi possível baixar o feed";
