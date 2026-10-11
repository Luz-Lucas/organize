import { createHash, randomBytes } from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import http from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { loadConfig, type McpConfig } from '../src/config.js';
import { buildApp } from '../src/http.js';
import { hashPassphrase } from '../src/oauth/passphrase.js';

export const PASS = 'senha-de-teste-123';
export const USER_ID = '00000000-0000-4000-8000-000000000001';
export const SECRET = 'x'.repeat(48);
export const REDIRECT = 'https://claude.ai/api/mcp/auth_callback';

let cachedHash: string | undefined;
export const passHash = () => (cachedHash ??= hashPassphrase(PASS));

export function pingServer(): McpServer {
  const s = new McpServer({ name: 'teste', version: '0.0.0' });
  s.registerTool('ping', { description: 'ping', inputSchema: { x: z.string().optional() } }, async () => ({
    content: [{ type: 'text', text: 'pong' }],
  }));
  return s;
}

export interface TestApp {
  url: string;
  cfg: McpConfig;
  dataDir: string;
  clock: { t: number };
  close: () => Promise<void>;
  restart: (overrides?: StartOpts) => Promise<TestApp>;
}

export interface StartOpts {
  dataDir?: string;
  clock?: { t: number };
  registerPerHour?: number;
  registerGlobalPerHour?: number;
  authorizeGetPer10Min?: number;
  /** Troca a senha de acesso (hash) / o segredo JWT, para testar a revogação por "geração". */
  passphraseHash?: string;
  secret?: string;
  /** Porta fixa (o restart reaproveita a anterior para a URL pública, iss e aud não mudarem). */
  port?: number;
}

export async function startApp(opts: StartOpts = {}): Promise<TestApp> {
  const dataDir = opts.dataDir ?? mkdtempSync(join(tmpdir(), 'mcp-test-'));
  const clock = opts.clock ?? { t: Date.parse('2026-10-12T12:00:00Z') };
  const server = http.createServer();
  await new Promise<void>((r) => server.listen(opts.port ?? 0, '127.0.0.1', r));
  const port = (server.address() as { port: number }).port;
  const url = `http://127.0.0.1:${port}`;
  const cfg = loadConfig({
    MCP_PUBLIC_URL: url, MCP_JWT_SECRET: opts.secret ?? SECRET, MCP_PASSPHRASE_HASH: opts.passphraseHash ?? passHash(), MCP_DATA_DIR: dataDir,
    SUPABASE_URL: 'http://x', SUPABASE_SERVICE_ROLE_KEY: 'k', ORGANIZACIONAL_USER_ID: USER_ID,
  });
  const handler = buildApp(cfg, {
    makeServer: pingServer, now: () => new Date(clock.t), registerPerHour: opts.registerPerHour ?? 10_000,
    registerGlobalPerHour: opts.registerGlobalPerHour ?? 10_000, authorizeGetPer10Min: opts.authorizeGetPer10Min ?? 10_000,
  });
  // Sem keep-alive: o restart reaproveita a porta e uma conexão reutilizada do pool falharia.
  server.on('request', (req, res) => { res.setHeader('Connection', 'close'); handler(req, res); });
  const app: TestApp = {
    url, cfg, dataDir, clock,
    close: () => new Promise<void>((r) => { server.closeAllConnections(); server.close(() => r()); }),
    restart: async (overrides = {}) => { await app.close(); return startApp({ ...opts, dataDir, clock, port, ...overrides }); },
  };
  return app;
}

export function cleanup(app: TestApp): Promise<void> {
  return app.close().then(() => rmSync(app.dataDir, { recursive: true, force: true }));
}

export function makePkce() {
  const verifier = randomBytes(40).toString('base64url');
  return { verifier, challenge: createHash('sha256').update(verifier).digest('base64url') };
}

export async function register(app: TestApp, redirect = REDIRECT, name = 'Teste'): Promise<string> {
  const r = await fetch(`${app.url}/register`, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ redirect_uris: [redirect], token_endpoint_auth_method: 'none', client_name: name }),
  });
  return (await r.json()).client_id;
}

export function authQuery(clientId: string, challenge: string, extra: Record<string, string> = {}): URLSearchParams {
  return new URLSearchParams({
    response_type: 'code', client_id: clientId, redirect_uri: REDIRECT,
    code_challenge: challenge, code_challenge_method: 'S256', state: 'est ado&1', ...extra,
  });
}

/** GET /authorize e devolve o CSRF (campo + cookie). */
export async function getForm(app: TestApp, q: URLSearchParams, headers: Record<string, string> = {}) {
  const r = await fetch(`${app.url}/authorize?${q}`, { redirect: 'manual', headers });
  const html = await r.text();
  const csrf = /name="csrf" value="([^"]+)"/.exec(html)?.[1] ?? '';
  const cookie = (r.headers.get('set-cookie') ?? '').split(';')[0];
  return { res: r, html, csrf, cookie };
}

export async function postAuthorize(
  app: TestApp, q: URLSearchParams, password: string, csrf: string, cookie: string, headers: Record<string, string> = {},
) {
  const body = new URLSearchParams(q);
  body.set('password', password);
  body.set('csrf', csrf);
  return fetch(`${app.url}/authorize`, {
    method: 'POST', redirect: 'manual',
    headers: { 'content-type': 'application/x-www-form-urlencoded', cookie, ...headers },
    body,
  });
}

/** Fluxo completo até o código. */
export async function getCode(app: TestApp, clientId: string, challenge: string, password = PASS) {
  const q = authQuery(clientId, challenge);
  const f = await getForm(app, q);
  const res = await postAuthorize(app, q, password, f.csrf, f.cookie);
  const loc = res.headers.get('location');
  return { res, location: loc, code: loc ? new URL(loc).searchParams.get('code') : null };
}

export async function tokenRequest(app: TestApp, params: Record<string, string>) {
  const r = await fetch(`${app.url}/token`, {
    method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(params),
  });
  return { status: r.status, body: await r.json() };
}

export async function fullLogin(app: TestApp) {
  const clientId = await register(app);
  const { verifier, challenge } = makePkce();
  const { code } = await getCode(app, clientId, challenge);
  const t = await tokenRequest(app, {
    grant_type: 'authorization_code', code: code!, code_verifier: verifier, client_id: clientId, redirect_uri: REDIRECT,
  });
  return { clientId, tokens: t.body as { access_token: string; refresh_token: string; expires_in: number } };
}
