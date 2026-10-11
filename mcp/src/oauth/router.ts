import { randomBytes, timingSafeEqual } from 'node:crypto';
import express, { type Request, type Response } from 'express';
import type { McpConfig } from '../config.js';
import { CHALLENGE_RE, verifyS256 } from './pkce.js';
import { verifyPassphrase } from './passphrase.js';
import { HitLimiter, LoginLimiter } from './ratelimit.js';
import { ACCESS_TTL_SECONDS, audience, signAccessToken } from './tokens.js';
import { OAuthStore, type OAuthClient } from './store.js';

const CSRF_TTL_MS = 15 * 60_000;
const MAX_CSRF = 500;
const GRANTS = ['authorization_code', 'refresh_token'];

const str = (v: unknown): string | undefined => (typeof v === 'string' ? v : undefined);

const esc = (s: string) =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');

function safeEqual(a: string, b: string): boolean {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
}

function noStore(res: Response): void {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Pragma', 'no-cache');
}

function oauthError(res: Response, status: number, error: string, description?: string): void {
  noStore(res);
  res.status(status).json(description ? { error, error_description: description } : { error });
}

function redirectUriAllowed(cfg: McpConfig, uri: string): boolean {
  if (uri.length > 2000 || /[\u0000- \u007f\\]/.test(uri)) return false;
  let u: URL;
  try { u = new URL(uri); } catch { return false; }
  if (u.username || u.password || u.hash) return false;
  if (u.protocol !== 'https:' && u.protocol !== 'http:') return false;
  return cfg.allowedRedirects.some((re) => re.test(uri));
}

export function createOAuthRouter(
  cfg: McpConfig, store: OAuthStore, now: () => Date, opts: { registerPerHour?: number } = {},
): express.Router {
  const router = express.Router();
  const secureCookie = cfg.publicUrl.startsWith('https://');
  const loginLimiter = new LoginLimiter(now);
  const registerLimiter = new HitLimiter(now, opts.registerPerHour ?? 20, 60 * 60_000);
  const csrfTokens = new Map<string, number>(); // token -> expiração

  // ---------- metadados ----------
  const protectedResource = (_req: Request, res: Response) => {
    res.json({
      resource: audience(cfg),
      authorization_servers: [cfg.publicUrl],
      bearer_methods_supported: ['header'],
    });
  };
  router.get('/.well-known/oauth-protected-resource', protectedResource);
  router.get('/.well-known/oauth-protected-resource/mcp', protectedResource);

  const serverMetadata = (_req: Request, res: Response) => {
    res.json({
      issuer: cfg.publicUrl,
      authorization_endpoint: `${cfg.publicUrl}/authorize`,
      token_endpoint: `${cfg.publicUrl}/token`,
      registration_endpoint: `${cfg.publicUrl}/register`,
      revocation_endpoint: `${cfg.publicUrl}/revoke`,
      response_types_supported: ['code'],
      grant_types_supported: GRANTS,
      code_challenge_methods_supported: ['S256'],
      token_endpoint_auth_methods_supported: ['none'],
      revocation_endpoint_auth_methods_supported: ['none'],
    });
  };
  router.get('/.well-known/oauth-authorization-server', serverMetadata);
  router.get('/.well-known/oauth-authorization-server/mcp', serverMetadata);

  // ---------- registro dinâmico (RFC 7591) ----------
  router.post('/register', (req, res) => {
    noStore(res);
    if (!registerLimiter.allow(req.ip ?? 'unknown')) {
      return oauthError(res, 429, 'temporarily_unavailable', 'Muitos registros. Tente mais tarde.');
    }
    const body = (req.body && typeof req.body === 'object' ? req.body : {}) as Record<string, unknown>;
    const uris = body.redirect_uris;
    if (!Array.isArray(uris) || uris.length < 1 || uris.length > 5 || !uris.every((u) => typeof u === 'string')) {
      return oauthError(res, 400, 'invalid_redirect_uri', 'redirect_uris deve ser uma lista de 1 a 5 URLs.');
    }
    if (!uris.every((u: string) => redirectUriAllowed(cfg, u))) {
      return oauthError(res, 400, 'invalid_redirect_uri', 'redirect_uri não permitido.');
    }
    const method = body.token_endpoint_auth_method;
    if (method !== undefined && method !== 'none') {
      return oauthError(res, 400, 'invalid_client_metadata', 'Só token_endpoint_auth_method "none" é aceito.');
    }
    if (body.grant_types !== undefined
      && !(Array.isArray(body.grant_types) && body.grant_types.every((g) => typeof g === 'string' && GRANTS.includes(g)))) {
      return oauthError(res, 400, 'invalid_client_metadata', 'grant_types não suportado.');
    }
    const name = typeof body.client_name === 'string' ? body.client_name.slice(0, 100) : undefined;
    const client = store.registerClient([...new Set(uris as string[])], name);
    if (!client) return oauthError(res, 400, 'invalid_client_metadata', 'Limite de clientes atingido.');
    res.status(201).json({
      client_id: client.clientId,
      client_id_issued_at: Math.floor(client.createdAt / 1000),
      client_name: client.clientName,
      redirect_uris: client.redirectUris,
      token_endpoint_auth_method: 'none',
      grant_types: GRANTS,
      response_types: ['code'],
    });
  });

  // ---------- /authorize ----------
  interface AuthParams {
    client: OAuthClient;
    redirectUri: string;
    codeChallenge: string;
    state?: string;
  }
  type Validation =
    | { kind: 'page'; message: string }
    | { kind: 'redirect'; redirectUri: string; state?: string; error: string; description: string }
    | { kind: 'ok'; p: AuthParams };

  function validateAuth(params: Record<string, unknown>): Validation {
    const clientId = str(params.client_id);
    const redirectUri = str(params.redirect_uri);
    const client = clientId ? store.getClient(clientId) : undefined;
    // Sem client/redirect_uri confiável NUNCA se redireciona (evita open redirect).
    if (!client) return { kind: 'page', message: 'Aplicativo desconhecido.' };
    if (!redirectUri || !client.redirectUris.some((u) => safeEqual(u, redirectUri))) {
      return { kind: 'page', message: 'Endereço de retorno não registrado.' };
    }
    const state = str(params.state);
    if (state !== undefined && state.length > 2048) return { kind: 'page', message: 'Requisição inválida.' };
    const fail = (error: string, description: string): Validation => ({ kind: 'redirect', redirectUri, state, error, description });
    if (str(params.response_type) !== 'code') return fail('unsupported_response_type', 'Só response_type=code é suportado.');
    const challenge = str(params.code_challenge);
    if (!challenge || !CHALLENGE_RE.test(challenge)) return fail('invalid_request', 'code_challenge ausente ou inválido.');
    if (str(params.code_challenge_method) !== 'S256') return fail('invalid_request', 'code_challenge_method deve ser S256.');
    return { kind: 'ok', p: { client, redirectUri, codeChallenge: challenge, state } };
  }

  function redirectWith(res: Response, redirectUri: string, params: Record<string, string | undefined>): void {
    const u = new URL(redirectUri);
    for (const [k, v] of Object.entries(params)) if (v !== undefined) u.searchParams.set(k, v);
    noStore(res);
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.redirect(302, u.toString());
  }

  function pageHeaders(res: Response, formActionOrigin?: string): void {
    noStore(res);
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'no-referrer');
    // O Chrome também aplica form-action ao redirecionamento após o envio: inclui só a origem
    // do redirect_uri já validado (exato) para o retorno ao Claude não ser bloqueado.
    res.setHeader('Content-Security-Policy',
      `default-src 'none'; style-src 'unsafe-inline'; form-action 'self'${formActionOrigin ? ` ${formActionOrigin}` : ''}; frame-ancestors 'none'; base-uri 'none'`);
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
  }

  const layout = (body: string) => `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex">
<title>Organizacional — autorizar acesso</title><style>
body{font:16px system-ui,sans-serif;background:#f4f4f6;margin:0;display:flex;min-height:100vh;align-items:center;justify-content:center}
main{background:#fff;padding:2rem;border-radius:12px;max-width:380px;width:calc(100% - 2rem);box-shadow:0 2px 12px #0002}
h1{font-size:1.2rem;margin-top:0}input[type=password]{width:100%;box-sizing:border-box;padding:.7rem;font-size:1rem;margin:.5rem 0 1rem}
button{width:100%;padding:.7rem;font-size:1rem;border:0;border-radius:8px;background:#3d5afe;color:#fff}.err{color:#b00020}
</style></head><body><main>${body}</main></body></html>`;

  function errorPage(res: Response, status: number, message: string, extra?: (r: Response) => void): void {
    pageHeaders(res);
    extra?.(res);
    res.status(status).send(layout(`<h1>Não foi possível continuar</h1><p>${esc(message)}</p>`));
  }

  function newCsrf(res: Response): string {
    const t = now().getTime();
    for (const [k, exp] of csrfTokens) if (exp < t) csrfTokens.delete(k);
    while (csrfTokens.size >= MAX_CSRF) csrfTokens.delete(csrfTokens.keys().next().value as string);
    const token = randomBytes(24).toString('base64url');
    csrfTokens.set(token, t + CSRF_TTL_MS);
    res.append('Set-Cookie', `mcp_csrf=${token}; Path=/authorize; HttpOnly; SameSite=Strict; Max-Age=${CSRF_TTL_MS / 1000}${secureCookie ? '; Secure' : ''}`);
    return token;
  }

  function cookie(req: Request, name: string): string | undefined {
    for (const part of (req.headers.cookie ?? '').split(';')) {
      const i = part.indexOf('=');
      if (i > 0 && part.slice(0, i).trim() === name) return part.slice(i + 1).trim();
    }
    return undefined;
  }

  function renderForm(res: Response, p: AuthParams, error?: string, status = 200): void {
    pageHeaders(res, new URL(p.redirectUri).origin);
    const csrf = newCsrf(res);
    const hidden = (n: string, v: string | undefined) => (v === undefined ? '' : `<input type="hidden" name="${n}" value="${esc(v)}">`);
    const who = p.client.clientName ? ` O aplicativo <b>${esc(p.client.clientName)}</b> pede` : ' Um aplicativo pede';
    res.status(status).send(layout(`<h1>Organizacional</h1>
<p>${who} acesso à sua agenda, tarefas, notas e casa. Digite sua senha de acesso para autorizar.</p>
${error ? `<p class="err" role="alert">${esc(error)}</p>` : ''}
<form method="post" action="/authorize" autocomplete="off">
${hidden('response_type', 'code')}${hidden('client_id', p.client.clientId)}${hidden('redirect_uri', p.redirectUri)}
${hidden('code_challenge', p.codeChallenge)}${hidden('code_challenge_method', 'S256')}${hidden('state', p.state)}${hidden('csrf', csrf)}
<label for="pw">Senha de acesso</label>
<input id="pw" type="password" name="password" required autofocus autocomplete="current-password">
<button type="submit">Autorizar</button></form>`));
  }

  router.get('/authorize', (req, res) => {
    const v = validateAuth(req.query as Record<string, unknown>);
    if (v.kind === 'page') return errorPage(res, 400, v.message);
    if (v.kind === 'redirect') return redirectWith(res, v.redirectUri, { error: v.error, error_description: v.description, state: v.state });
    renderForm(res, v.p);
  });

  router.post('/authorize', (req, res) => {
    const body = (req.body ?? {}) as Record<string, unknown>;
    const v = validateAuth(body);
    if (v.kind === 'page') return errorPage(res, 400, v.message);
    if (v.kind === 'redirect') return redirectWith(res, v.redirectUri, { error: v.error, error_description: v.description, state: v.state });

    const ip = req.ip ?? 'unknown';
    const wait = loginLimiter.blockedFor(ip);
    if (wait > 0) {
      return errorPage(res, 429, 'Muitas tentativas. Aguarde alguns minutos e tente de novo.', (r) => r.setHeader('Retry-After', String(wait)));
    }

    const csrf = str(body.csrf);
    const cookieCsrf = cookie(req, 'mcp_csrf');
    const exp = csrf ? csrfTokens.get(csrf) : undefined;
    if (!csrf || !cookieCsrf || !safeEqual(csrf, cookieCsrf) || exp === undefined || exp < now().getTime()) {
      return renderForm(res, v.p, 'A página expirou. Tente novamente.', 403);
    }
    csrfTokens.delete(csrf);

    const password = str(body.password);
    if (!password || password.length > 1024 || !verifyPassphrase(password, cfg.passphraseHash)) {
      loginLimiter.recordFailure(ip);
      return renderForm(res, v.p, 'Senha incorreta.', 401);
    }
    const code = store.issueCode(v.p.client.clientId, v.p.redirectUri, v.p.codeChallenge);
    redirectWith(res, v.p.redirectUri, { code, state: v.p.state });
  });

  // ---------- /token ----------
  router.post('/token', async (req, res) => {
    noStore(res);
    const body = (req.body ?? {}) as Record<string, unknown>;
    const grant = str(body.grant_type);
    const clientId = str(body.client_id);
    if (!grant) return oauthError(res, 400, 'invalid_request', 'grant_type ausente.');
    if (!clientId) return oauthError(res, 400, 'invalid_request', 'client_id ausente.');
    const client = store.getClient(clientId);
    if (!client) return oauthError(res, 401, 'invalid_client');

    const issue = async (family: string) => {
      const accessToken = await signAccessToken(cfg, now());
      const refreshToken = store.issueRefresh(family, client.clientId);
      res.json({ access_token: accessToken, token_type: 'Bearer', expires_in: ACCESS_TTL_SECONDS, refresh_token: refreshToken });
    };

    if (grant === 'authorization_code') {
      const code = str(body.code);
      const verifier = str(body.code_verifier);
      const redirectUri = str(body.redirect_uri);
      if (!code || !verifier || !redirectUri) return oauthError(res, 400, 'invalid_request', 'code, code_verifier e redirect_uri são obrigatórios.');
      const entry = store.takeCode(code); // consome sempre: uso único mesmo em caso de erro
      if (!entry
        || !safeEqual(entry.clientId, client.clientId)
        || !safeEqual(entry.redirectUri, redirectUri)
        || !verifyS256(verifier, entry.codeChallenge)) {
        return oauthError(res, 400, 'invalid_grant');
      }
      return issue(entry.family);
    }

    if (grant === 'refresh_token') {
      const token = str(body.refresh_token);
      if (!token) return oauthError(res, 400, 'invalid_request', 'refresh_token ausente.');
      const family = store.rotateRefresh(token, client.clientId);
      if (!family) return oauthError(res, 400, 'invalid_grant');
      return issue(family);
    }

    oauthError(res, 400, 'unsupported_grant_type');
  });

  // ---------- /revoke (RFC 7009) ----------
  router.post('/revoke', (req, res) => {
    noStore(res);
    const token = str((req.body ?? {}).token);
    if (token) store.revokeToken(token);
    res.status(200).json({});
  });

  return router;
}
