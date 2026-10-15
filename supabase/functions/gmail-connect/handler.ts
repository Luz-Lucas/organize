import {
  bearer,
  buildConsentUrl,
  CORS,
  type GmailConfig,
  type GoogleProvider,
  isProvider,
  json,
  signState,
  userAllowed,
  validEmail,
} from "../_shared/gmail.ts";

export interface ConnectDeps {
  cfg: GmailConfig | null;
  getUserId: (jwt: string) => Promise<string | null>;
  /** GOOGLE_ALLOWED_USER_ID: se definido, só esse usuário conecta. */
  allowedUserId?: string;
  now?: () => number;
}

/** POST { provider?: "gmail" | "drive", email?: string } -> { url }. Padrão: gmail. Identifica o usuário pelo JWT. */
export async function handle(req: Request, deps: ConnectDeps): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (req.method !== "POST") return json({ error: "método não permitido" }, 405);
  if (!deps.cfg) return json({ error: "serviço não configurado" }, 500);

  const jwt = bearer(req);
  const userId = jwt ? await deps.getUserId(jwt).catch(() => null) : null;
  if (!userId) return json({ error: "não autorizado" }, 401);
  if (!userAllowed(deps.allowedUserId, userId)) return json({ error: "não permitido" }, 403);

  const body = await req.json().catch(() => ({}));
  const hint = (body as { email?: unknown })?.email;
  const rawProvider = (body as { provider?: unknown })?.provider;
  if (rawProvider !== undefined && rawProvider !== null && !isProvider(rawProvider)) {
    return json({ error: "serviço desconhecido" }, 400);
  }
  const provider: GoogleProvider = rawProvider ?? "gmail";
  if (hint !== undefined && hint !== null && hint !== "" && !validEmail(hint)) {
    return json({ error: "e-mail inválido" }, 400);
  }

  const state = await signState(userId, deps.cfg.stateSecret, deps.now?.() ?? Date.now(), undefined, provider);
  return json({ url: buildConsentUrl(deps.cfg, state, validEmail(hint) ? hint : undefined, provider) });
}
