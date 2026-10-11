import { SignJWT } from 'jose';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { LoginLimiter } from '../src/oauth/ratelimit.js';
import {
  PASS, REDIRECT, SECRET, USER_ID, authQuery, cleanup, fullLogin, getCode, getForm, makePkce, postAuthorize,
  register, startApp, tokenRequest, type TestApp,
} from './oauth-helpers.js';

let app: TestApp;
beforeAll(async () => { app = await startApp(); });
afterAll(async () => { await cleanup(app); });

const grantBody = (clientId: string, code: string, verifier: string, redirect = REDIRECT) => ({
  grant_type: 'authorization_code', code, code_verifier: verifier, client_id: clientId, redirect_uri: redirect,
});

describe('metadados', () => {
  it('protected-resource e authorization-server', async () => {
    const pr = await (await fetch(`${app.url}/.well-known/oauth-protected-resource`)).json();
    expect(pr).toMatchObject({ resource: `${app.url}/mcp`, authorization_servers: [app.url] });
    const as = await (await fetch(`${app.url}/.well-known/oauth-authorization-server`)).json();
    expect(as).toMatchObject({
      issuer: app.url,
      authorization_endpoint: `${app.url}/authorize`,
      token_endpoint: `${app.url}/token`,
      registration_endpoint: `${app.url}/register`,
      code_challenge_methods_supported: ['S256'],
      token_endpoint_auth_methods_supported: ['none'],
    });
    expect(as.grant_types_supported).toEqual(['authorization_code', 'refresh_token']);
  });
});

describe('/register', () => {
  const post = (body: unknown) => fetch(`${app.url}/register`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body),
  });
  it('aceita redirect_uri permitido (claude e loopback)', async () => {
    const r = await post({ redirect_uris: [REDIRECT, 'http://localhost:6274/cb'] });
    expect(r.status).toBe(201);
    expect((await r.json()).client_id).toBeTruthy();
  });
  it('recusa redirect_uri fora da lista', async () => {
    for (const uri of ['https://evil.example/cb', 'https://claude.ai.evil.example/api/mcp/auth_callback',
      'http://localhost@evil.example/', 'https://claude.ai/api/mcp/auth_callback#x', 'javascript:alert(1)', 'https://claude.ai/api/mcp/auth_callback\n']) {
      const r = await post({ redirect_uris: [uri] });
      expect(r.status, uri).toBe(400);
      expect((await r.json()).error).toBe('invalid_redirect_uri');
    }
    expect((await post({})).status).toBe(400);
    expect((await post({ redirect_uris: REDIRECT })).status).toBe(400);
  });
  it('recusa método de autenticação diferente de none', async () => {
    const r = await post({ redirect_uris: [REDIRECT], token_endpoint_auth_method: 'client_secret_basic' });
    expect(r.status).toBe(400);
    expect((await r.json()).error).toBe('invalid_client_metadata');
  });
});

describe('/authorize', () => {
  it('mostra o formulário com CSRF e cabeçalhos seguros', async () => {
    const clientId = await register(app);
    const f = await getForm(app, authQuery(clientId, makePkce().challenge));
    expect(f.res.status).toBe(200);
    expect(f.html).toContain('type="password"');
    expect(f.csrf.length).toBeGreaterThan(20);
    expect(f.res.headers.get('x-frame-options')).toBe('DENY');
    expect(f.res.headers.get('cache-control')).toBe('no-store');
    expect(f.res.headers.get('content-security-policy')).toContain("default-src 'none'");
    expect(f.res.headers.get('content-security-policy')).toContain("form-action 'self'");
    expect(f.res.headers.get('referrer-policy')).toBe('no-referrer');
    expect(f.res.headers.get('set-cookie')).toMatch(/HttpOnly.*SameSite=Strict/i);
  });

  it('escapa valores no HTML (state malicioso)', async () => {
    const clientId = await register(app);
    const f = await getForm(app, authQuery(clientId, makePkce().challenge, { state: '"><script>alert(1)</script>' }));
    expect(f.html).not.toContain('<script>alert');
    expect(f.html).toContain('&lt;script&gt;');
  });

  it('senha correta redireciona com code e state', async () => {
    const clientId = await register(app);
    const { challenge } = makePkce();
    const { res, location } = await getCode(app, clientId, challenge);
    expect(res.status).toBe(302);
    const u = new URL(location!);
    expect(`${u.origin}${u.pathname}`).toBe(REDIRECT);
    expect(u.searchParams.get('code')!.length).toBeGreaterThanOrEqual(43);
    expect(u.searchParams.get('state')).toBe('est ado&1');
  });

  it('senha errada: formulário com erro, sem redirecionar; 6ª tentativa => 429', async () => {
    const app = await startApp(); // limitador próprio (por IP) para não afetar os outros testes
    const clientId = await register(app);
    const q = authQuery(clientId, makePkce().challenge);
    for (let i = 0; i < 5; i++) {
      const f = await getForm(app, q);
      const r = await postAuthorize(app, q, 'errada', f.csrf, f.cookie);
      expect(r.status).toBe(401);
      expect(r.headers.get('location')).toBeNull();
      expect(await r.text()).toContain('Senha incorreta');
    }
    const f = await getForm(app, q);
    const r = await postAuthorize(app, q, PASS, f.csrf, f.cookie); // até a senha certa é bloqueada
    expect(r.status).toBe(429);
    expect(r.headers.get('location')).toBeNull();
    expect(Number(r.headers.get('retry-after'))).toBeGreaterThan(0);
    await cleanup(app);
  });

  it('PKCE: plain, sem challenge ou method => erro; redirecionamento só para URI registrado', async () => {
    const clientId = await register(app);
    const { challenge } = makePkce();
    for (const q of [
      authQuery(clientId, challenge, { code_challenge_method: 'plain' }),
      authQuery(clientId, challenge, { code_challenge_method: '' }),
      (() => { const x = authQuery(clientId, challenge); x.delete('code_challenge'); return x; })(),
      authQuery(clientId, 'curto'),
    ]) {
      const r = await fetch(`${app.url}/authorize?${q}`, { redirect: 'manual' });
      expect(r.status).toBe(302);
      const u = new URL(r.headers.get('location')!);
      expect(`${u.origin}${u.pathname}`).toBe(REDIRECT);
      expect(u.searchParams.get('error')).toBe('invalid_request');
      expect(u.searchParams.get('code')).toBeNull();
    }
  });

  it('redirect_uri diferente do registrado ou client_id desconhecido => erro SEM redirecionar', async () => {
    const clientId = await register(app);
    const { challenge } = makePkce();
    for (const q of [
      authQuery(clientId, challenge, { redirect_uri: 'https://evil.example/cb' }),
      authQuery(clientId, challenge, { redirect_uri: REDIRECT + '/' }),
      authQuery(clientId, challenge, { redirect_uri: 'http://localhost:1/cb' }),
      authQuery('desconhecido', challenge),
    ]) {
      const r = await fetch(`${app.url}/authorize?${q}`, { redirect: 'manual' });
      expect(r.status).toBe(400);
      expect(r.headers.get('location')).toBeNull();
    }
    // POST também revalida: redirect_uri adulterado no formulário não gera código
    const q = authQuery(clientId, challenge);
    const f = await getForm(app, q);
    const q2 = authQuery(clientId, challenge, { redirect_uri: 'https://evil.example/cb' });
    const r = await postAuthorize(app, q2, PASS, f.csrf, f.cookie);
    expect(r.status).toBe(400);
    expect(r.headers.get('location')).toBeNull();
  });

  it('CSRF: sem cookie ou token trocado => recusa mesmo com a senha certa', async () => {
    const clientId = await register(app);
    const q = authQuery(clientId, makePkce().challenge);
    const f = await getForm(app, q);
    const noCookie = await postAuthorize(app, q, PASS, f.csrf, '');
    expect(noCookie.status).toBe(403);
    expect(noCookie.headers.get('location')).toBeNull();
    const wrong = await postAuthorize(app, q, PASS, 'inventado', f.cookie);
    expect(wrong.status).toBe(403);
    // token é de uso único
    const ok = await postAuthorize(app, q, PASS, f.csrf, f.cookie);
    expect(ok.status).toBe(302);
    const again = await postAuthorize(app, q, PASS, f.csrf, f.cookie);
    expect(again.status).toBe(403);
  });
});

describe('LoginLimiter', () => {
  it('20 falhas por hora no total bloqueiam qualquer IP; janela por IP expira em 15 min', () => {
    let t = 0;
    const l = new LoginLimiter(() => new Date(t));
    for (let i = 0; i < 5; i++) l.recordFailure('a');
    expect(l.blockedFor('a')).toBeGreaterThan(0);
    expect(l.blockedFor('b')).toBe(0);
    t += 15 * 60_000 + 1;
    expect(l.blockedFor('a')).toBe(0);
    for (let i = 0; i < 20; i++) l.recordFailure(`ip${i}`);
    expect(l.blockedFor('novo')).toBeGreaterThan(0);
    t += 60 * 60_000 + 1;
    expect(l.blockedFor('novo')).toBe(0);
  });
});

describe('limite de /register', () => {
  it('21º registro do mesmo IP na hora => 429', async () => {
    const a = await startApp({ registerPerHour: 20 });
    const codes: number[] = [];
    for (let i = 0; i < 21; i++) {
      const r = await fetch(`${a.url}/register`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ redirect_uris: [REDIRECT] }) });
      codes.push(r.status);
    }
    expect(codes.slice(0, 20).every((c) => c === 201)).toBe(true);
    expect(codes[20]).toBe(429);
    await cleanup(a);
  });
  it('com 50 clientes sem refresh ativo, o mais antigo é substituído', async () => {
    const a = await startApp();
    const first = await register(a);
    for (let i = 0; i < 50; i++) await register(a);
    const q = authQuery(first, makePkce().challenge);
    expect((await fetch(`${a.url}/authorize?${q}`)).status).toBe(400); // o primeiro foi removido
    await cleanup(a);
  });
});

describe('/token', () => {
  it('fluxo completo devolve access_token (JWT) e refresh_token', async () => {
    const { tokens } = await fullLogin(app);
    expect(tokens.access_token.split('.')).toHaveLength(3);
    expect(tokens.refresh_token.length).toBeGreaterThanOrEqual(43);
    expect(tokens.expires_in).toBe(3600);
  });

  it('código usado duas vezes: 2ª invalid_grant e o refresh emitido pela 1ª é revogado', async () => {
    const clientId = await register(app);
    const { verifier, challenge } = makePkce();
    const { code } = await getCode(app, clientId, challenge);
    const first = await tokenRequest(app, grantBody(clientId, code!, verifier));
    expect(first.status).toBe(200);
    const second = await tokenRequest(app, grantBody(clientId, code!, verifier));
    expect(second.status).toBe(400);
    expect(second.body).toEqual({ error: 'invalid_grant' });
    expect(second.body.access_token).toBeUndefined();
    const r = await tokenRequest(app, { grant_type: 'refresh_token', refresh_token: first.body.refresh_token, client_id: clientId });
    expect(r.body.error).toBe('invalid_grant');
  });

  it('code_verifier, redirect_uri ou client_id errados => invalid_grant (e o código é queimado)', async () => {
    const clientId = await register(app);
    const other = await register(app);
    const { verifier, challenge } = makePkce();
    const cases: Array<[string, (code: string) => Record<string, string>]> = [
      ['verifier', (c) => grantBody(clientId, c, makePkce().verifier)],
      ['redirect', (c) => grantBody(clientId, c, verifier, 'http://localhost:1/cb')],
      ['client', (c) => grantBody(other, c, verifier)],
    ];
    for (const [name, build] of cases) {
      const { code } = await getCode(app, clientId, challenge);
      const bad = await tokenRequest(app, build(code!));
      expect(bad.status, name).toBe(400);
      expect(bad.body.error, name).toBe('invalid_grant');
      expect(bad.body.access_token).toBeUndefined();
      const retry = await tokenRequest(app, grantBody(clientId, code!, verifier));
      expect(retry.body.error, `${name}-retry`).toBe('invalid_grant');
    }
  });

  it('código expirado (relógio injetado) => invalid_grant', async () => {
    const clientId = await register(app);
    const { verifier, challenge } = makePkce();
    const { code } = await getCode(app, clientId, challenge);
    app.clock.t += 5 * 60_000 + 1000;
    const r = await tokenRequest(app, grantBody(clientId, code!, verifier));
    app.clock.t -= 5 * 60_000 + 1000;
    expect(r.body).toEqual({ error: 'invalid_grant' });
  });

  it('erros de formato OAuth', async () => {
    expect((await tokenRequest(app, {})).body.error).toBe('invalid_request');
    expect((await tokenRequest(app, { grant_type: 'password', client_id: 'x' })).body.error).toBe('invalid_client');
    const clientId = await register(app);
    expect((await tokenRequest(app, { grant_type: 'password', client_id: clientId })).body.error).toBe('unsupported_grant_type');
    expect((await tokenRequest(app, { grant_type: 'authorization_code', client_id: clientId })).body.error).toBe('invalid_request');
  });

  it('respostas de token não são cacheáveis', async () => {
    const r = await fetch(`${app.url}/token`, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: 'grant_type=x' });
    expect(r.headers.get('cache-control')).toBe('no-store');
  });
});

describe('refresh token', () => {
  it('rotaciona; reuso do antigo => invalid_grant e o novo da família também cai', async () => {
    const { clientId, tokens } = await fullLogin(app);
    const r1 = await tokenRequest(app, { grant_type: 'refresh_token', refresh_token: tokens.refresh_token, client_id: clientId });
    expect(r1.status).toBe(200);
    expect(r1.body.refresh_token).not.toBe(tokens.refresh_token);
    expect(r1.body.access_token).toBeTruthy();
    const reuse = await tokenRequest(app, { grant_type: 'refresh_token', refresh_token: tokens.refresh_token, client_id: clientId });
    expect(reuse.status).toBe(400);
    expect(reuse.body).toEqual({ error: 'invalid_grant' });
    const fresh = await tokenRequest(app, { grant_type: 'refresh_token', refresh_token: r1.body.refresh_token, client_id: clientId });
    expect(fresh.body).toEqual({ error: 'invalid_grant' });
  });

  it('client_id diferente, token inventado ou expirado => invalid_grant', async () => {
    const { clientId, tokens } = await fullLogin(app);
    const other = await register(app);
    expect((await tokenRequest(app, { grant_type: 'refresh_token', refresh_token: tokens.refresh_token, client_id: other })).body.error).toBe('invalid_grant');
    expect((await tokenRequest(app, { grant_type: 'refresh_token', refresh_token: 'inventado', client_id: clientId })).body.error).toBe('invalid_grant');
    app.clock.t += 31 * 24 * 3600_000;
    const expired = await tokenRequest(app, { grant_type: 'refresh_token', refresh_token: tokens.refresh_token, client_id: clientId });
    app.clock.t -= 31 * 24 * 3600_000;
    expect(expired.body.error).toBe('invalid_grant');
  });

  it('/revoke invalida a família; responde 200 mesmo para token desconhecido', async () => {
    const { clientId, tokens } = await fullLogin(app);
    const rv = await fetch(`${app.url}/revoke`, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ token: tokens.refresh_token }) });
    expect(rv.status).toBe(200);
    expect((await tokenRequest(app, { grant_type: 'refresh_token', refresh_token: tokens.refresh_token, client_id: clientId })).body.error).toBe('invalid_grant');
    const unknown = await fetch(`${app.url}/revoke`, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: 'token=nada' });
    expect(unknown.status).toBe(200);
  });
});

describe('persistência', () => {
  it('clientes e refresh sobrevivem a reinício; refresh.json guarda só hash', async () => {
    const a = await startApp();
    try {
      const { clientId, tokens } = await fullLogin(a);
      const raw = readFileSync(join(a.dataDir, 'refresh.json'), 'utf8');
      expect(raw).not.toContain(tokens.refresh_token);
      const b = await a.restart();
      Object.assign(a, { close: b.close });
      const r = await tokenRequest(b, { grant_type: 'refresh_token', refresh_token: tokens.refresh_token, client_id: clientId });
      expect(r.status).toBe(200);
      await cleanup(b);
    } finally { /* dataDir removido acima */ }
  });

  it('tolera arquivos corrompidos', async () => {
    const a = await startApp();
    writeFileSync(join(a.dataDir, 'clients.json'), '{nao-json');
    writeFileSync(join(a.dataDir, 'refresh.json'), '[1,"x",null]');
    const b = await a.restart();
    expect((await fetch(`${b.url}/.well-known/oauth-protected-resource`)).status).toBe(200);
    expect(await register(b)).toBeTruthy();
    await cleanup(b);
  });
});

describe('/mcp: autenticação', () => {
  const init = { jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-03-26', capabilities: {}, clientInfo: { name: 't', version: '1' } } };
  const call = (headers: Record<string, string>) => fetch(`${app.url}/mcp`, {
    method: 'POST', headers: { 'content-type': 'application/json', accept: 'application/json, text/event-stream', ...headers }, body: JSON.stringify(init),
  });
  const meta = () => `resource_metadata="${app.url}/.well-known/oauth-protected-resource"`;
  const jwt = (o: { secret?: string; aud?: string; iss?: string; sub?: string; exp?: number } = {}) => {
    const nowS = Math.floor(app.clock.t / 1000);
    return new SignJWT({}).setProtectedHeader({ alg: 'HS256' })
      .setIssuer(o.iss ?? app.url).setAudience(o.aud ?? `${app.url}/mcp`).setSubject(o.sub ?? USER_ID)
      .setIssuedAt(nowS - 10).setExpirationTime(o.exp ?? nowS + 600)
      .sign(new TextEncoder().encode(o.secret ?? SECRET));
  };

  it('sem Authorization => 401 com resource_metadata', async () => {
    const r = await call({});
    expect(r.status).toBe(401);
    expect(r.headers.get('www-authenticate')).toContain(meta());
    expect(r.headers.get('www-authenticate')).toMatch(/^Bearer /);
  });

  it('JWT válido controle => 200', async () => {
    expect((await call({ authorization: `Bearer ${await jwt()}` })).status).toBe(200);
  });

  it('expirado, aud errado, iss errado, sub errado, segredo errado, alg none, lixo => 401', async () => {
    const nowS = Math.floor(app.clock.t / 1000);
    const none = `${Buffer.from('{"alg":"none"}').toString('base64url')}.${Buffer.from(JSON.stringify({ iss: app.url, aud: `${app.url}/mcp`, sub: USER_ID, exp: nowS + 600 })).toString('base64url')}.`;
    const tokens = [
      await jwt({ exp: nowS - 5 }),
      await jwt({ aud: 'https://outro.example/mcp' }),
      await jwt({ iss: 'https://outro.example' }),
      await jwt({ sub: 'outro-usuario' }),
      await jwt({ secret: 'y'.repeat(48) }),
      none,
      'lixo',
    ];
    for (const t of tokens) {
      const r = await call({ authorization: `Bearer ${t}` });
      expect(r.status, t.slice(0, 20)).toBe(401);
      expect(r.headers.get('www-authenticate')).toContain(meta());
    }
    expect((await call({ authorization: `Basic abc` })).status).toBe(401);
  });

  it('access_token emitido expira após 1 h (relógio injetado)', async () => {
    const { tokens } = await fullLogin(app);
    expect((await call({ authorization: `Bearer ${tokens.access_token}` })).status).toBe(200);
    app.clock.t += 3600_000 + 2000;
    const r = await call({ authorization: `Bearer ${tokens.access_token}` });
    app.clock.t -= 3600_000 + 2000;
    expect(r.status).toBe(401);
  });

  it('GET e DELETE exigem token e depois respondem 405 (modo sem sessão)', async () => {
    expect((await fetch(`${app.url}/mcp`)).status).toBe(401);
    const { tokens } = await fullLogin(app);
    const r = await fetch(`${app.url}/mcp`, { method: 'DELETE', headers: { authorization: `Bearer ${tokens.access_token}` } });
    expect(r.status).toBe(405);
  });
});

describe('CORS', () => {
  it('permite claude.ai e claude.com, nega outras origens', async () => {
    for (const origin of ['https://claude.ai', 'https://claude.com']) {
      const r = await fetch(`${app.url}/.well-known/oauth-authorization-server`, { headers: { origin } });
      expect(r.headers.get('access-control-allow-origin')).toBe(origin);
    }
    const evil = await fetch(`${app.url}/.well-known/oauth-authorization-server`, { headers: { origin: 'https://evil.example' } });
    expect(evil.headers.get('access-control-allow-origin')).toBeNull();
    const evilPost = await fetch(`${app.url}/token`, { method: 'POST', headers: { origin: 'https://claude.ai.evil.example', 'content-type': 'application/x-www-form-urlencoded' }, body: 'grant_type=x' });
    expect(evilPost.headers.get('access-control-allow-origin')).toBeNull();
  });
  it('OPTIONS responde 204 (com cabeçalhos só para origem permitida)', async () => {
    const ok = await fetch(`${app.url}/mcp`, { method: 'OPTIONS', headers: { origin: 'https://claude.ai', 'access-control-request-method': 'POST' } });
    expect(ok.status).toBe(204);
    expect(ok.headers.get('access-control-allow-origin')).toBe('https://claude.ai');
    expect(ok.headers.get('access-control-allow-headers')).toMatch(/authorization/i);
    const bad = await fetch(`${app.url}/mcp`, { method: 'OPTIONS', headers: { origin: 'https://evil.example' } });
    expect(bad.status).toBe(204);
    expect(bad.headers.get('access-control-allow-origin')).toBeNull();
  });
  it('/mcp recusa origem de navegador não permitida (403)', async () => {
    const r = await fetch(`${app.url}/mcp`, { method: 'POST', headers: { origin: 'https://evil.example', 'content-type': 'application/json' }, body: '{}' });
    expect(r.status).toBe(403);
  });
});
