// Helpers compartilhados das Edge Functions do Gmail.
// Escopo pedido: gmail.modify (permite marcar como lida). O app continua lendo só cabeçalhos
// (format=metadata) e guardando remetente, assunto e data; nunca corpo nem anexos.
// Regra de log: nunca registrar assunto, endereços, tokens nem corpo de resposta do Google.

export const GMAIL_SCOPE = "https://www.googleapis.com/auth/gmail.modify";
/** Escopo das contas conectadas antes do "marcar como lida": ainda vale para ler, mas não para alterar. */
export const GMAIL_LEGACY_SCOPE = "https://www.googleapis.com/auth/gmail.metadata";
/** Drive inteiro (pastas existentes, mover, compartilhar). Refresh token cifrado como o do Gmail. */
export const DRIVE_SCOPE = "https://www.googleapis.com/auth/drive";

export type GoogleProvider = "gmail" | "drive";
export const PROVIDERS: readonly GoogleProvider[] = ["gmail", "drive"];
export const isProvider = (v: unknown): v is GoogleProvider => v === "gmail" || v === "drive";
export const scopeFor = (p: GoogleProvider): string => p === "drive" ? DRIVE_SCOPE : GMAIL_SCOPE;

const scopeList = (scopes: string | null | undefined): string[] => (scopes ?? "").split(/\s+/).filter(Boolean);

/** O `scope` devolvido pelo Google basta para o provider? Gmail aceita modify e o antigo metadata. */
export function scopeGranted(p: GoogleProvider, scopes: string | null | undefined): boolean {
  const list = scopeList(scopes);
  if (p === "drive") return list.includes(DRIVE_SCOPE);
  return list.includes(GMAIL_SCOPE) || list.includes(GMAIL_LEGACY_SCOPE);
}

/** A conta tem permissão para alterar mensagens (gmail.modify)? */
export const hasModifyScope = (scopes: string | null | undefined): boolean => scopeList(scopes).includes(GMAIL_SCOPE);
export const GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth";
export const GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";
export const GOOGLE_REVOKE_URL = "https://oauth2.googleapis.com/revoke";
export const GMAIL_API = "https://gmail.googleapis.com/gmail/v1";
export const INBOX_LIMIT = 15;
export const STATE_TTL_MS = 10 * 60 * 1000;
export const HTTP_TIMEOUT_MS = 10_000;

export type FetchFn = typeof fetch;

export interface GmailConfig {
  clientId: string;
  clientSecret: string;
  tokenKey: string; // base64, 32 bytes
  stateSecret: string;
  redirectUri: string;
}

/** Lê os segredos do ambiente. Retorna null se faltar algum (a função responde 500 genérico). */
export function loadConfig(get: (k: string) => string | undefined): GmailConfig | null {
  const clientId = get("GOOGLE_CLIENT_ID");
  const clientSecret = get("GOOGLE_CLIENT_SECRET");
  const tokenKey = get("GMAIL_TOKEN_KEY");
  const stateSecret = get("STATE_SECRET");
  const base = get("SUPABASE_URL");
  if (!clientId || !clientSecret || !tokenKey || !stateSecret || !base) return null;
  return {
    clientId,
    clientSecret,
    tokenKey,
    stateSecret,
    redirectUri: `${base.replace(/\/+$/, "")}/functions/v1/gmail-callback`,
  };
}

// ---------------------------------------------------------------- base64

export function b64encode(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s);
}

export function b64decode(text: string): Uint8Array<ArrayBuffer> {
  const bin = atob(text);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function b64urlEncode(bytes: Uint8Array): string {
  return b64encode(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function b64urlDecode(text: string): Uint8Array<ArrayBuffer> {
  if (!/^[A-Za-z0-9_-]*$/.test(text)) throw new Error("base64url inválido");
  const padded = text.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((text.length + 3) % 4);
  return b64decode(padded);
}

const enc = new TextEncoder();

// ---------------------------------------------------------------- comparação segura

/** Comparação em tempo constante (via SHA-256 dos dois lados). */
export async function safeEqual(a: string, b: string): Promise<boolean> {
  const [ha, hb] = await Promise.all([
    crypto.subtle.digest("SHA-256", enc.encode(a)),
    crypto.subtle.digest("SHA-256", enc.encode(b)),
  ]);
  const x = new Uint8Array(ha);
  const y = new Uint8Array(hb);
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}

// ---------------------------------------------------------------- AES-256-GCM (refresh token)

async function aesKey(keyB64: string): Promise<CryptoKey> {
  let raw: Uint8Array<ArrayBuffer>;
  try {
    raw = b64decode(keyB64.trim());
  } catch {
    throw new Error("GMAIL_TOKEN_KEY inválida");
  }
  if (raw.length !== 32) throw new Error("GMAIL_TOKEN_KEY deve ter 32 bytes");
  return await crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"]);
}

/** Saída: base64(iv[12] || ciphertext+tag). */
export async function encryptToken(plain: string, keyB64: string): Promise<string> {
  const key = await aesKey(keyB64);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, enc.encode(plain)));
  const out = new Uint8Array(iv.length + ct.length);
  out.set(iv, 0);
  out.set(ct, iv.length);
  return b64encode(out);
}

/** Lança se o dado foi adulterado, a chave é outra ou o formato é inválido. */
export async function decryptToken(blob: string, keyB64: string): Promise<string> {
  const key = await aesKey(keyB64);
  let data: Uint8Array<ArrayBuffer>;
  try {
    data = b64decode(blob);
  } catch {
    throw new Error("token cifrado inválido");
  }
  if (data.length < 12 + 16) throw new Error("token cifrado inválido");
  const iv = data.slice(0, 12);
  const ct = data.slice(12);
  try {
    return new TextDecoder().decode(await crypto.subtle.decrypt({ name: "AES-GCM", iv }, key, ct));
  } catch {
    throw new Error("token cifrado inválido");
  }
}

/** Alguma das linhas (de outro provider do mesmo usuário) tem este e-mail? Sem diferenciar maiúsculas. */
export function siblingMatches(rows: { account_email: string }[] | null, accountEmail: string): boolean {
  const want = accountEmail.trim().toLowerCase();
  return (rows ?? []).some((r) => typeof r.account_email === "string" && r.account_email.trim().toLowerCase() === want);
}

// ---------------------------------------------------------------- state do OAuth

async function hmacKey(secret: string, usages: KeyUsage[]): Promise<CryptoKey> {
  return await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, usages);
}

/**
 * state = base64url(userId.expiresAt.nonce[.provider]) + "." + base64url(HMAC-SHA256(payloadB64)).
 * O provider só entra no payload quando não é "gmail" (o formato do Gmail não muda).
 */
export async function signState(
  userId: string,
  secret: string,
  now: number = Date.now(),
  ttlMs: number = STATE_TTL_MS,
  provider: GoogleProvider = "gmail",
): Promise<string> {
  const nonce = b64urlEncode(crypto.getRandomValues(new Uint8Array(16)));
  const base = `${userId}.${now + ttlMs}.${nonce}`;
  const payload = b64urlEncode(enc.encode(provider === "gmail" ? base : `${base}.${provider}`));
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", await hmacKey(secret, ["sign"]), enc.encode(payload)));
  return `${payload}.${b64urlEncode(sig)}`;
}

/** Como verifyStateInfo, mas também devolve o nonce (para uso único no callback). */
export async function verifyStateFull(
  state: string,
  secret: string,
  now: number = Date.now(),
): Promise<{ userId: string; provider: GoogleProvider; nonce: string } | null> {
  try {
    const parts = state.split(".");
    if (parts.length !== 2) return null;
    const [payload, sigB64] = parts;
    const sig = b64urlDecode(sigB64);
    const ok = await crypto.subtle.verify("HMAC", await hmacKey(secret, ["verify"]), sig, enc.encode(payload));
    if (!ok) return null;
    const [userId, exp, nonce, provider, extra] = new TextDecoder().decode(b64urlDecode(payload)).split(".");
    if (!userId || !exp || !nonce || extra !== undefined) return null;
    if (provider !== undefined && !isProvider(provider)) return null;
    if (!/^\d+$/.test(exp) || Number(exp) < now) return null;
    return { userId, provider: provider ?? "gmail", nonce };
  } catch {
    return null;
  }
}

/** Retorna userId e provider se a assinatura confere (tempo constante) e não expirou; senão null. */
export async function verifyStateInfo(
  state: string,
  secret: string,
  now: number = Date.now(),
): Promise<{ userId: string; provider: GoogleProvider } | null> {
  const full = await verifyStateFull(state, secret, now);
  return full ? { userId: full.userId, provider: full.provider } : null;
}

/** Guarda de nonces já usados: `consume` devolve true só na primeira vez que o nonce aparece. */
export interface NonceStore {
  consume(nonce: string): Promise<boolean>;
}

/**
 * O cadastro do Supabase é aberto: com GOOGLE_ALLOWED_USER_ID definido, só esse usuário pode conectar
 * Google. Sem o segredo, vale qualquer usuário autenticado (comportamento anterior) e o log avisa.
 */
export function userAllowed(allowedUserId: string | undefined | null, userId: string): boolean {
  const allowed = allowedUserId?.trim();
  if (!allowed) {
    console.warn("google: GOOGLE_ALLOWED_USER_ID não definido; qualquer usuário autenticado pode conectar o Google");
    return true;
  }
  return allowed.toLowerCase() === userId.toLowerCase();
}

/** Retorna o userId se o state é válido (qualquer provider); senão null. */
export async function verifyState(
  state: string,
  secret: string,
  now: number = Date.now(),
): Promise<string | null> {
  return (await verifyStateInfo(state, secret, now))?.userId ?? null;
}

// ---------------------------------------------------------------- URL de consentimento

export function buildConsentUrl(
  cfg: GmailConfig,
  state: string,
  loginHint?: string,
  provider: GoogleProvider = "gmail",
): string {
  const p = new URLSearchParams({
    client_id: cfg.clientId,
    redirect_uri: cfg.redirectUri,
    response_type: "code",
    scope: scopeFor(provider),
    access_type: "offline",
    prompt: "consent",
    include_granted_scopes: "false",
    state,
  });
  if (loginHint) p.set("login_hint", loginHint);
  return `${GOOGLE_AUTH_URL}?${p.toString()}`;
}

const EMAIL_RE = /^[^\s@<>()",;:\\]{1,64}@[A-Za-z0-9.-]{1,255}\.[A-Za-z]{2,}$/;
export function validEmail(v: unknown): v is string {
  return typeof v === "string" && v.length <= 254 && EMAIL_RE.test(v);
}

// ---------------------------------------------------------------- chamadas ao Google

/** "scope" = o token não tem a permissão pedida (só vem de batchModifyRead). */
export type GoogleErrorKind = "auth" | "transient" | "other" | "scope";

/** Mensagem sempre genérica: nunca inclui corpo da resposta nem tokens. */
export class GoogleError extends Error {
  constructor(public kind: GoogleErrorKind, public status = 0) {
    super(`google:${kind}:${status}`);
    this.name = "GoogleError";
  }
}

const RATE_REASONS = new Set(["rateLimitExceeded", "userRateLimitExceeded", "dailyLimitExceeded", "quotaExceeded"]);

export async function readJson(res: Response): Promise<Record<string, unknown>> {
  try {
    const v = await res.json();
    return v && typeof v === "object" ? v as Record<string, unknown> : {};
  } catch {
    return {};
  }
}

/** Classifica uma resposta de erro do Google (corpo já lido) sem vazar detalhes. */
export function classify(status: number, body: Record<string, unknown>, tokenEndpoint: boolean): GoogleError {
  if (status === 429 || status >= 500) return new GoogleError("transient", status);
  if (tokenEndpoint) {
    // invalid_grant = token revogado/expirado; invalid_client/unauthorized_client = credenciais do app
    // erradas (problema de configuração, não do usuário) -> erro genérico.
    if (body.error === "invalid_grant") return new GoogleError("auth", status);
    if (status === 401 || status === 403) return new GoogleError("auth", status);
    return new GoogleError("other", status);
  }
  if (status === 401) return new GoogleError("auth", status);
  if (status === 403) {
    const errs = (body.error as { errors?: { reason?: string }[] } | undefined)?.errors;
    if (Array.isArray(errs) && errs.some((e) => e.reason && RATE_REASONS.has(e.reason))) {
      return new GoogleError("transient", status);
    }
    return new GoogleError("auth", status);
  }
  return new GoogleError("other", status);
}

export async function request(
  fetchFn: FetchFn,
  url: string,
  init: RequestInit,
  tokenEndpoint = false,
  allow404 = false,
): Promise<Record<string, unknown> | null> {
  let res: Response;
  try {
    res = await fetchFn(url, { ...init, signal: AbortSignal.timeout(HTTP_TIMEOUT_MS) });
  } catch {
    throw new GoogleError("transient");
  }
  if (res.ok) return await readJson(res);
  if (allow404 && res.status === 404) {
    await res.body?.cancel().catch(() => {});
    return null;
  }
  throw classify(res.status, await readJson(res), tokenEndpoint);
}

const form = (data: Record<string, string>) => ({
  method: "POST",
  headers: { "Content-Type": "application/x-www-form-urlencoded" },
  body: new URLSearchParams(data).toString(),
});

export interface TokenExchange {
  refreshToken: string | null;
  accessToken: string;
  scope: string;
}

export async function exchangeCode(cfg: GmailConfig, code: string, fetchFn: FetchFn): Promise<TokenExchange> {
  const j = await request(
    fetchFn,
    GOOGLE_TOKEN_URL,
    form({
      code,
      client_id: cfg.clientId,
      client_secret: cfg.clientSecret,
      redirect_uri: cfg.redirectUri,
      grant_type: "authorization_code",
    }),
    true,
  );
  const accessToken = typeof j?.access_token === "string" ? j.access_token : "";
  if (!accessToken) throw new GoogleError("other");
  return {
    accessToken,
    refreshToken: typeof j?.refresh_token === "string" && j.refresh_token ? j.refresh_token : null,
    scope: typeof j?.scope === "string" ? j.scope : "",
  };
}

export async function refreshAccessToken(cfg: GmailConfig, refreshToken: string, fetchFn: FetchFn): Promise<string> {
  const j = await request(
    fetchFn,
    GOOGLE_TOKEN_URL,
    form({
      refresh_token: refreshToken,
      client_id: cfg.clientId,
      client_secret: cfg.clientSecret,
      grant_type: "refresh_token",
    }),
    true,
  );
  if (typeof j?.access_token !== "string" || !j.access_token) throw new GoogleError("other");
  return j.access_token;
}

/** Melhor esforço: nunca lança. */
export async function revokeToken(token: string, fetchFn: FetchFn): Promise<boolean> {
  try {
    const res = await fetchFn(GOOGLE_REVOKE_URL, { ...form({ token }), signal: AbortSignal.timeout(HTTP_TIMEOUT_MS) });
    await res.body?.cancel().catch(() => {});
    return res.ok;
  } catch {
    return false;
  }
}

const authz = (accessToken: string) => ({ Authorization: `Bearer ${accessToken}` });

export async function getProfileEmail(accessToken: string, fetchFn: FetchFn): Promise<string> {
  const j = await request(fetchFn, `${GMAIL_API}/users/me/profile`, { headers: authz(accessToken) });
  const email = typeof j?.emailAddress === "string" ? j.emailAddress : "";
  if (!email) throw new GoogleError("other");
  return email;
}

export async function getInboxUnread(accessToken: string, fetchFn: FetchFn): Promise<number> {
  const j = await request(fetchFn, `${GMAIL_API}/users/me/labels/INBOX`, { headers: authz(accessToken) });
  const n = j?.messagesUnread;
  return typeof n === "number" && Number.isFinite(n) && n >= 0 ? Math.floor(n) : 0;
}

/** 403 por falta de escopo (≠ limite de taxa, ≠ token revogado). */
function insufficientScope(body: Record<string, unknown>): boolean {
  const err = body.error as { errors?: { reason?: string }[]; details?: { reason?: string }[] } | undefined;
  const reasons = [...(Array.isArray(err?.errors) ? err!.errors! : []), ...(Array.isArray(err?.details) ? err!.details! : [])]
    .map((e) => e?.reason);
  return reasons.includes("insufficientPermissions") || reasons.includes("ACCESS_TOKEN_SCOPE_INSUFFICIENT");
}

/**
 * Tira o rótulo UNREAD de até 100 mensagens (messages.batchModify; responde 204).
 * Lança GoogleError("scope") quando o token não tem gmail.modify.
 */
export async function batchMarkRead(accessToken: string, ids: string[], fetchFn: FetchFn): Promise<void> {
  let res: Response;
  try {
    res = await fetchFn(`${GMAIL_API}/users/me/messages/batchModify`, {
      method: "POST",
      headers: { ...authz(accessToken), "Content-Type": "application/json" },
      body: JSON.stringify({ ids, removeLabelIds: ["UNREAD"] }),
      signal: AbortSignal.timeout(HTTP_TIMEOUT_MS),
    });
  } catch {
    throw new GoogleError("transient");
  }
  if (res.ok) {
    await res.body?.cancel().catch(() => {});
    return;
  }
  const body = await readJson(res);
  if (res.status === 403 && insufficientScope(body)) throw new GoogleError("scope", 403);
  throw classify(res.status, body, false);
}

/** Não usa o parâmetro `q`: o escopo metadata o proíbe. */
export async function listInboxIds(accessToken: string, fetchFn: FetchFn, max = INBOX_LIMIT): Promise<string[]> {
  const p = new URLSearchParams({ maxResults: String(max) });
  p.append("labelIds", "INBOX");
  const j = await request(fetchFn, `${GMAIL_API}/users/me/messages?${p}`, { headers: authz(accessToken) });
  const list = Array.isArray(j?.messages) ? j!.messages as { id?: unknown }[] : [];
  return list.map((m) => m.id).filter((id): id is string => typeof id === "string" && /^[A-Za-z0-9_-]+$/.test(id));
}

export interface EmailItem {
  gmail_id: string;
  thread_id: string | null;
  from_name: string | null;
  from_addr: string | null;
  subject: string | null;
  received_at: string | null;
  unread: boolean;
}

/** Retorna null se a mensagem sumiu entre a listagem e a leitura (404). */
export async function getMessageMeta(accessToken: string, id: string, fetchFn: FetchFn): Promise<EmailItem | null> {
  const p = new URLSearchParams({ format: "metadata" });
  for (const h of ["From", "Subject", "Date"]) p.append("metadataHeaders", h);
  const j = await request(
    fetchFn,
    `${GMAIL_API}/users/me/messages/${encodeURIComponent(id)}?${p}`,
    { headers: authz(accessToken) },
    false,
    true,
  );
  if (!j) return null;
  return parseMessage(id, j);
}

// ---------------------------------------------------------------- cabeçalhos

const MAX_NAME = 200;
const MAX_SUBJECT = 500;

// deno-lint-ignore no-control-regex
const CTRL = /[\u0000-\u001f\u007f]/g;
const clean = (s: string) => s.replace(CTRL, " ").replace(/\s+/g, " ").trim();

function decodeBytes(bytes: Uint8Array, charset: string): string {
  const cs = charset.split("*")[0].toLowerCase(); // RFC 2231: charset*lang
  try {
    return new TextDecoder(cs === "utf8" ? "utf-8" : cs).decode(bytes);
  } catch {
    return new TextDecoder("utf-8").decode(bytes);
  }
}

/** Decodifica palavras codificadas RFC 2047 (=?charset?B|Q?texto?=). */
export function decodeEncodedWords(input: string): string {
  // Espaço entre duas palavras codificadas adjacentes é descartado (RFC 2047 §6.2).
  const joined = input.replace(/(\?=)[ \t\r\n]+(?==\?[^?\s]+\?[bBqQ]\?)/g, "$1");
  return joined.replace(/=\?([^?\s]+)\?([bBqQ])\?([^?\s]*)\?=/g, (whole, charset: string, kind: string, text: string) => {
    try {
      let bytes: Uint8Array;
      if (kind.toLowerCase() === "b") {
        bytes = b64decode(text);
      } else {
        const q = text.replace(/_/g, " ");
        const out: number[] = [];
        for (let i = 0; i < q.length; i++) {
          if (q[i] === "=" && /^[0-9A-Fa-f]{2}$/.test(q.slice(i + 1, i + 3))) {
            out.push(parseInt(q.slice(i + 1, i + 3), 16));
            i += 2;
          } else {
            out.push(q.charCodeAt(i) & 0xff);
          }
        }
        bytes = new Uint8Array(out);
      }
      return decodeBytes(bytes, charset);
    } catch {
      return whole;
    }
  });
}

/** Primeiro mailbox de uma lista, respeitando aspas, <...> e comentários (...). */
function firstMailbox(raw: string): string {
  let quoted = false;
  let angle = 0;
  let paren = 0;
  for (let i = 0; i < raw.length; i++) {
    const c = raw[i];
    if (c === "\\" && (quoted || paren > 0)) {
      i++;
    } else if (c === '"' && paren === 0) {
      quoted = !quoted;
    } else if (!quoted) {
      if (c === "(") paren++;
      else if (c === ")" && paren > 0) paren--;
      else if (paren === 0) {
        if (c === "<") angle++;
        else if (c === ">" && angle > 0) angle--;
        else if (c === "," && angle === 0) return raw.slice(0, i);
      }
    }
  }
  return raw;
}

function unquote(s: string): string {
  const t = s.trim();
  if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) return t.slice(1, -1).replace(/\\(.)/g, "$1");
  return t.replace(/\\(.)/g, "$1");
}

const ADDR_RE = /[^\s<>()",;:\\@]+@[^\s<>()",;:\\@]+/;

/** Separa "Nome <a@b>", `"Nome, X" <a@b>`, "a@b (Nome)", "<a@b>", "a@b" e encoded-words. */
export function parseFrom(raw: string | null | undefined): { name: string | null; addr: string | null } {
  if (!raw) return { name: null, addr: null };
  const mailbox = firstMailbox(raw).trim();
  let name = "";
  let addr = "";
  const lt = mailbox.lastIndexOf("<");
  const gt = mailbox.lastIndexOf(">");
  if (lt !== -1 && gt > lt) {
    addr = mailbox.slice(lt + 1, gt).trim();
    name = mailbox.slice(0, lt);
  } else {
    const m = mailbox.match(ADDR_RE);
    if (m) {
      addr = m[0];
      const comment = mailbox.match(/\(([^)]*)\)\s*$/);
      name = comment ? comment[1] : mailbox.replace(m[0], "");
    } else {
      name = mailbox;
    }
  }
  // "route": <@dominio:a@b> -> pega só o endereço final
  const am = addr.match(ADDR_RE);
  addr = am ? am[0] : "";
  name = clean(decodeEncodedWords(unquote(name)));
  if (name.toLowerCase() === addr.toLowerCase()) name = "";
  return {
    name: name ? name.slice(0, MAX_NAME) : null,
    addr: addr ? addr.toLowerCase().slice(0, 254) : null,
  };
}

export function parseSubject(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const s = clean(decodeEncodedWords(raw));
  return s ? s.slice(0, MAX_SUBJECT) : null;
}

function headerValue(headers: unknown, name: string): string | null {
  if (!Array.isArray(headers)) return null;
  const h = headers.find((x) => typeof x?.name === "string" && x.name.toLowerCase() === name.toLowerCase());
  return typeof h?.value === "string" ? h.value : null;
}

/** Converte a resposta de messages.get (format=metadata) em linha de email_items. */
export function parseMessage(id: string, msg: Record<string, unknown>): EmailItem {
  const payload = msg.payload as { headers?: unknown } | undefined;
  const from = parseFrom(headerValue(payload?.headers, "From"));
  const subject = parseSubject(headerValue(payload?.headers, "Subject"));
  // internalDate = hora de recebimento (não falsificável); o cabeçalho Date é só reserva.
  let received: Date | null = null;
  const internal = typeof msg.internalDate === "string" && /^\d+$/.test(msg.internalDate)
    ? new Date(Number(msg.internalDate))
    : null;
  if (internal && !isNaN(internal.getTime())) received = internal;
  if (!received) {
    const d = headerValue(payload?.headers, "Date");
    const parsed = d ? new Date(d) : null;
    if (parsed && !isNaN(parsed.getTime())) received = parsed;
  }
  const labels = Array.isArray(msg.labelIds) ? msg.labelIds : [];
  return {
    gmail_id: id,
    thread_id: typeof msg.threadId === "string" ? msg.threadId : null,
    from_name: from.name,
    from_addr: from.addr,
    subject,
    received_at: received ? received.toISOString() : null,
    unread: labels.includes("UNREAD"),
  };
}

// ---------------------------------------------------------------- HTTP

export const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export const json = (body: unknown, status = 200): Response =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...CORS },
  });

export function bearer(req: Request): string {
  const h = req.headers.get("authorization") ?? "";
  return h.startsWith("Bearer ") ? h.slice("Bearer ".length) : "";
}
