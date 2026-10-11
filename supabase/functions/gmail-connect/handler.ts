import { bearer, buildConsentUrl, CORS, type GmailConfig, json, signState, validEmail } from "../_shared/gmail.ts";

export interface ConnectDeps {
  cfg: GmailConfig | null;
  getUserId: (jwt: string) => Promise<string | null>;
  now?: () => number;
}

/** POST { email?: string } -> { url }. Identifica o usuário pelo JWT. */
export async function handle(req: Request, deps: ConnectDeps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (req.method !== "POST") return json({ error: "método não permitido" }, 405);
  if (!deps.cfg) return json({ error: "serviço não configurado" }, 500);

  const jwt = bearer(req);
  const userId = jwt ? await deps.getUserId(jwt).catch(() => null) : null;
  if (!userId) return json({ error: "não autorizado" }, 401);

  const body = await req.json().catch(() => ({}));
  const hint = (body as { email?: unknown })?.email;
  if (hint !== undefined && hint !== null && hint !== "" && !validEmail(hint)) {
    return json({ error: "e-mail inválido" }, 400);
  }

  const state = await signState(userId, deps.cfg.stateSecret, deps.now?.() ?? Date.now());
  return json({ url: buildConsentUrl(deps.cfg, state, validEmail(hint) ? hint : undefined) });
}
