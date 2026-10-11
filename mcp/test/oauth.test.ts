import { SignJWT } from 'jose';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { hashPassphrase } from '../src/oauth/passphrase.js';
import { HitLimiter, LoginLimiter, clientKey } from '../src/oauth/ratelimit.js';
import { OAuthStore, REVOKED_TTL_MS } from '../src/oauth/store.js';
import { generation } from '../src/oauth/tokens.js';
import {
  PASS, REDIRECT, SECRET, USER_ID, authQuery, cleanup, fullLogin, getCode, getForm, makePkce, passHash, postAuthorize,
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
  it('limita a 3 URIs e 512 caracteres no total', async () => {
    const loop = (n: number) => `http://localhost:${6000 + n}/cb`;
    expect((await post({ redirect_uris: [loop(1), loop(2), loop(3)] })).status).toBe(201);
    expect((await post({ redirect_uris: [loop(1), loop(2), loop(3), loop(4)] })).status).toBe(400);
    const long = (n: number) => `http://localhost:6000/${'a'.repeat(n)}`;
    expect((await post({ redirect_uris: [long(300), long(250)] })).status).toBe(400); // > 512 no total
    expect((await post({ redirect_uris: [long(200), long(250)] })).status).toBe(201);
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
    // o token é amarrado ao cookie: a própria dupla funciona, mas não com o cookie de outro formulário
    const f2 = await getForm(app, q);
    expect((await postAuthorize(app, q, PASS, f.csrf, f2.cookie)).status).toBe(403);
    expect((await postAuthorize(app, q, PASS, f2.csrf, f.cookie)).status).toBe(403);
    const ok = await postAuthorize(app, q, PASS, f.csrf, f.cookie);
    expect(ok.status).toBe(302);
  });

  it('CSRF sem estado: HMAC com expiração; adulterar expiração ou MAC, ou vencer, => 403', async () => {
    const a = await startApp();
    const clientId = await register(a);
    const q = authQuery(clientId, makePkce().challenge);
    const f = await getForm(a, q);
    const [exp, mac] = f.csrf.split('.');
    expect(Number(exp)).toBe(a.clock.t + 15 * 60_000);
    expect(mac).toMatch(/^[A-Za-z0-9_-]{43}$/);
    const forged = [`${Number(exp) + 3600_000}.${mac}`, `${exp}.${mac.slice(0, -1)}${mac.endsWith('A') ? 'B' : 'A'}`, `${exp}`, `.${mac}`, 'x.y'];
    for (const t of forged) expect((await postAuthorize(a, q, PASS, t, f.cookie)).status, t).toBe(403);
    // vencido
    a.clock.t += 15 * 60_000 + 1;
    expect((await postAuthorize(a, q, PASS, f.csrf, f.cookie)).status).toBe(403);
    a.clock.t -= 15 * 60_000 + 1;
    // não depende de memória: sobrevive a um reinício do servidor (mesmo segredo)
    const b = await a.restart();
    const cl = await register(b);
    const q2 = authQuery(cl, makePkce().challenge);
    const g = await getForm(b, q2);
    expect((await postAuthorize(b, q2, PASS, g.csrf, g.cookie)).status).toBe(302);
    // CSRF de uma instância com outro segredo não vale
    const c = await b.restart({ secret: 'z'.repeat(48) });
    const cl2 = await register(c);
    const q3 = authQuery(cl2, makePkce().challenge);
    const h = await getForm(c, q3);
    expect((await postAuthorize(c, q3, PASS, g.csrf, g.cookie)).status).toBe(403);
    expect((await postAuthorize(c, q3, PASS, h.csrf, h.cookie)).status).toBe(302);
    await cleanup(c);
  });

  it('o pool de CSRF não existe mais: milhares de GETs não invalidam um formulário aberto', async () => {
    const a = await startApp();
    const clientId = await register(a);
    const q = authQuery(clientId, makePkce().challenge);
    const mine = await getForm(a, q);
    for (let i = 0; i < 600; i++) await fetch(`${a.url}/authorize?${q}`);
    expect((await postAuthorize(a, q, PASS, mine.csrf, mine.cookie)).status).toBe(302);
    await cleanup(a);
  });

  it('GET /authorize tem limite por IP (60 em 10 min); outro IP não é afetado; janela expira', async () => {
    const a = await startApp({ authorizeGetPer10Min: 60 });
    const clientId = await register(a);
    const q = authQuery(clientId, makePkce().challenge);
    const get = (xff: string) => fetch(`${a.url}/authorize?${q}`, { headers: { 'x-forwarded-for': xff } });
    for (let i = 0; i < 60; i++) expect((await get('198.51.100.1')).status).toBe(200);
    const blocked = await get('198.51.100.1');
    expect(blocked.status).toBe(429);
    expect(blocked.headers.get('retry-after')).toBeTruthy();
    expect((await get('198.51.100.2')).status).toBe(200);
    a.clock.t += 10 * 60_000 + 1;
    expect((await get('198.51.100.1')).status).toBe(200);
    await cleanup(a);
  });

  it('página de consentimento mostra o host de retorno e só confia no client_name de claude.ai/claude.com', async () => {
    const claude = await register(app, REDIRECT, 'Claude');
    const f1 = await getForm(app, authQuery(claude, makePkce().challenge));
    expect(f1.html).toContain('Você está autorizando um app que enviará o acesso para:');
    expect(f1.html).toContain('<b>claude.ai</b>');
    expect(f1.html).toContain('<b>Claude</b>');
    const evil = await register(app, 'http://localhost:6274/cb', '<i>Claude Oficial</i>');
    const f2 = await getForm(app, new URLSearchParams({
      response_type: 'code', client_id: evil, redirect_uri: 'http://localhost:6274/cb', code_challenge: makePkce().challenge, code_challenge_method: 'S256',
    }));
    expect(f2.html).toContain('<b>localhost:6274</b>');
    expect(f2.html).toContain('App desconhecido');
    expect(f2.html).not.toContain('Claude Oficial');
    expect(f2.html).not.toContain('<i>');
  });
});

describe('chave de limite por cliente', () => {
  it('IPv4 como está; IPv6 pelo prefixo /64; IPv4 mapeado vira IPv4', () => {
    expect(clientKey('203.0.113.9')).toBe('203.0.113.9');
    expect(clientKey('::ffff:203.0.113.9')).toBe('203.0.113.9');
    const k = clientKey('2001:db8:1:2::1');
    expect(k).toBe(clientKey('2001:0db8:0001:0002:ffff:ffff:ffff:ffff'));
    expect(k).toBe(clientKey('2001:DB8:1:2:abcd::9'));
    expect(k).not.toBe(clientKey('2001:db8:1:3::1'));
    expect(clientKey('::1')).toBe('0000:0000:0000:0000::/64');
    expect(clientKey('fe80::1%eth0')).toBe(clientKey('fe80::2'));
    expect(clientKey('::1.2.3.4')).toBe('0000:0000:0000:0000::/64');
    expect(clientKey(undefined)).toBe('unknown');
    expect(clientKey('lixo')).toBe('unknown');
  });
});

describe('dono nunca fica trancado para fora', () => {
  it('um IP falhando a cada 3 min por 24 h simuladas não bloqueia outro IP', () => {
    let t = 0;
    const l = new LoginLimiter(() => new Date(t));
    for (let i = 0; i < 480; i++) {
      if (l.blockedFor('atacante') === 0) l.recordFailure('atacante');
      expect(l.blockedFor('dono'), `t=${i * 3}min`).toBe(0);
      t += 3 * 60_000;
    }
  });
  it('um IP martelando o máximo permitido por 24 h também não enche o teto global', () => {
    let t = 0;
    const l = new LoginLimiter(() => new Date(t));
    for (let i = 0; i < 24 * 60; i++) { // tenta a cada minuto
      if (l.blockedFor('atacante') === 0) l.recordFailure('atacante');
      expect(l.blockedFor('dono'), `t=${i}min`).toBe(0);
      t += 60_000;
    }
  });
  it('o teto global (200/h) ainda protege de inundação distribuída', () => {
    let t = 0;
    const l = new LoginLimiter(() => new Date(t));
    for (let i = 0; i < 199; i++) l.recordFailure(`k${i}`);
    expect(l.blockedFor('dono')).toBe(0);
    l.recordFailure('k199');
    expect(l.blockedFor('dono')).toBeGreaterThan(0);
    t += 60 * 60_000 + 1;
    expect(l.blockedFor('dono')).toBe(0);
  });
  it('HTTP: IP bloqueado não impede outro IP de entrar; /64 IPv6 divide o mesmo limite', async () => {
    const a = await startApp();
    const clientId = await register(a);
    const q = authQuery(clientId, makePkce().challenge);
    const attempt = async (xff: string, password: string) => {
      const f = await getForm(a, q, { 'x-forwarded-for': xff });
      return postAuthorize(a, q, password, f.csrf, f.cookie, { 'x-forwarded-for': xff });
    };
    for (let i = 0; i < 5; i++) expect((await attempt('198.51.100.7', 'errada')).status).toBe(401);
    expect((await attempt('198.51.100.7', 'errada')).status).toBe(429);
    const owner = await attempt('203.0.113.9', PASS);
    expect(owner.status).toBe(302);
    expect(new URL(owner.headers.get('location')!).searchParams.get('code')).toBeTruthy();
    // IPv6: endereços diferentes do mesmo /64 contam juntos
    const base = ['2001:db8:1:2::1', '2001:db8:1:2:aaaa::2', '2001:db8:1:2::3', '2001:db8:1:2:bbbb::4', '2001:db8:1:2::5'];
    for (const ip of base) expect((await attempt(ip, 'errada')).status).toBe(401);
    expect((await attempt('2001:db8:1:2:cccc::6', 'errada')).status).toBe(429);
    expect((await attempt('2001:db8:1:3::1', 'errada')).status).toBe(401); // outro /64
    await cleanup(a);
  });
});

describe('LoginLimiter', () => {
  it('200 falhas por hora no total bloqueiam qualquer IP; janela por IP expira em 15 min', () => {
    let t = 0;
    const l = new LoginLimiter(() => new Date(t));
    for (let i = 0; i < 5; i++) l.recordFailure('a');
    expect(l.blockedFor('a')).toBeGreaterThan(0);
    expect(l.blockedFor('b')).toBe(0);
    t += 15 * 60_000 + 1;
    expect(l.blockedFor('a')).toBe(0);
    for (let i = 0; i < 200; i++) l.recordFailure(`ip${i}`);
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
  it('com 50 clientes sem refresh ativo, o mais antigo (com mais de 10 min) é substituído', async () => {
    const a = await startApp();
    const first = await register(a);
    a.clock.t += 11 * 60_000; // o primeiro deixa de estar "recente"
    for (let i = 0; i < 49; i++) await register(a);
    const q = authQuery(first, makePkce().challenge);
    expect((await fetch(`${a.url}/authorize?${q}`)).status).toBe(200); // ainda cabe: 50 clientes
    await register(a); // 51º: despeja o mais antigo
    expect((await fetch(`${a.url}/authorize?${q}`)).status).toBe(400);
    await cleanup(a);
  });
  it('nunca despeja cliente registrado há menos de 10 min: store cheio de recentes => 429', async () => {
    const a = await startApp();
    const ids: string[] = [];
    for (let i = 0; i < 50; i++) ids.push(await register(a));
    const r = await fetch(`${a.url}/register`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ redirect_uris: [REDIRECT] }) });
    expect(r.status).toBe(429);
    expect((await r.json()).error).toBe('temporarily_unavailable');
    const q = authQuery(ids[0], makePkce().challenge);
    expect((await fetch(`${a.url}/authorize?${q}`)).status).toBe(200); // o primeiro continua lá
    a.clock.t += 10 * 60_000; // passados 10 min já pode ser substituído
    expect((await register(a))).toBeTruthy();
    await cleanup(a);
  });
  it('teto global de 50 registros por hora (IPs diferentes), restaurado depois de 1 h', async () => {
    const a = await startApp({ registerPerHour: 100, registerGlobalPerHour: 50 });
    const post = (xff: string) => fetch(`${a.url}/register`, {
      method: 'POST', headers: { 'content-type': 'application/json', 'x-forwarded-for': xff }, body: JSON.stringify({ redirect_uris: [REDIRECT] }),
    });
    // 10 IPs x 5 registros; como o store comporta 50, espaçar não é preciso (todos cabem)
    for (let i = 0; i < 50; i++) expect((await post(`198.51.100.${i % 10}`)).status, `#${i}`).toBe(201);
    expect((await post('198.51.100.99')).status).toBe(429);
    a.clock.t += 60 * 60_000 + 1;
    expect((await post('198.51.100.99')).status).toBe(201);
    await cleanup(a);
  });
  it('limite de /register por /64 IPv6', async () => {
    const a = await startApp({ registerPerHour: 3 });
    const post = (xff: string) => fetch(`${a.url}/register`, {
      method: 'POST', headers: { 'content-type': 'application/json', 'x-forwarded-for': xff }, body: JSON.stringify({ redirect_uris: [REDIRECT] }),
    });
    for (const ip of ['2001:db8:9:9::1', '2001:db8:9:9:1::2', '2001:db8:9:9::3']) expect((await post(ip)).status).toBe(201);
    expect((await post('2001:db8:9:9:ffff::4')).status).toBe(429);
    expect((await post('2001:db8:9:8::1')).status).toBe(201);
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
  const jwt = (o: { secret?: string; aud?: string; iss?: string; sub?: string; exp?: number; claims?: Record<string, unknown> } = {}) => {
    const nowS = Math.floor(app.clock.t / 1000);
    return new SignJWT(o.claims ?? { gen: generation(app.cfg), fid: 'familia-teste' }).setProtectedHeader({ alg: 'HS256' })
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
      await jwt({ claims: {} }), // sem gen/fid
      await jwt({ claims: { gen: generation(app.cfg) } }), // sem fid
      await jwt({ claims: { fid: 'f' } }), // sem gen
      await jwt({ claims: { gen: '0123456789abcdef', fid: 'f' } }), // geração errada
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

describe('revogação', () => {
  const DAY = 24 * 3600_000;
  const initBody = JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-03-26', capabilities: {}, clientInfo: { name: 't', version: '1' } } });
  const mcp = (a: TestApp, access: string) => fetch(`${a.url}/mcp`, {
    method: 'POST', body: initBody,
    headers: { 'content-type': 'application/json', accept: 'application/json, text/event-stream', authorization: `Bearer ${access}` },
  });
  const refresh = (a: TestApp, clientId: string, token: string) =>
    tokenRequest(a, { grant_type: 'refresh_token', refresh_token: token, client_id: clientId });
  const revoke = (a: TestApp, token: string) => fetch(`${a.url}/revoke`, {
    method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ token }),
  });

  it('família tem teto absoluto de 30 dias a partir do código: a rotação não o estende', async () => {
    const a = await startApp();
    const issuedAt = a.clock.t;
    const { clientId, tokens } = await fullLogin(a);
    a.clock.t += 20 * DAY;
    const r1 = await refresh(a, clientId, tokens.refresh_token);
    expect(r1.status).toBe(200);
    a.clock.t += 9 * DAY; // dia 29
    const r2 = await refresh(a, clientId, r1.body.refresh_token);
    expect(r2.status).toBe(200);
    const rows = JSON.parse(readFileSync(join(a.dataDir, 'refresh.json'), 'utf8')) as Array<{ familyExpiresAt: number; expiresAt: number }>;
    expect(rows).toHaveLength(3);
    for (const row of rows) {
      expect(row.familyExpiresAt).toBe(issuedAt + 30 * DAY);
      expect(row.expiresAt).toBeLessThanOrEqual(issuedAt + 30 * DAY);
    }
    a.clock.t += 2 * DAY; // dia 31: o último refresh (válido por 30 d "pela regra antiga") já não vale
    const r3 = await refresh(a, clientId, r2.body.refresh_token);
    expect(r3.body).toEqual({ error: 'invalid_grant' });
    await cleanup(a);
  });

  it('trocar a senha de acesso invalida access e refresh tokens existentes', async () => {
    const a = await startApp();
    const { clientId, tokens } = await fullLogin(a);
    expect((await mcp(a, tokens.access_token)).status).toBe(200);
    const b = await a.restart({ passphraseHash: hashPassphrase('outra-senha-bem-longa-1') });
    try {
      expect((await mcp(b, tokens.access_token)).status).toBe(401);
      expect(await refresh(b, clientId, tokens.refresh_token)).toMatchObject({ status: 400, body: { error: 'invalid_grant' } });
    } finally { await cleanup(b); }
  });

  it('trocar o segredo JWT invalida tudo (inclusive o refresh, que não depende da assinatura)', async () => {
    const a = await startApp();
    const { clientId, tokens } = await fullLogin(a);
    const b = await a.restart({ secret: 'k'.repeat(48) });
    try {
      expect((await mcp(b, tokens.access_token)).status).toBe(401);
      expect((await refresh(b, clientId, tokens.refresh_token)).body.error).toBe('invalid_grant');
      // e quem fizer login de novo recebe tokens da geração nova
      const again = await fullLogin(b);
      expect((await mcp(b, again.tokens.access_token)).status).toBe(200);
    } finally { await cleanup(b); }
  });

  it('mesma senha e segredo => mesma geração, e os tokens sobrevivem ao reinício', async () => {
    const a = await startApp();
    const { clientId, tokens } = await fullLogin(a);
    const b = await a.restart();
    try {
      expect((await mcp(b, tokens.access_token)).status).toBe(200);
      expect((await refresh(b, clientId, tokens.refresh_token)).status).toBe(200);
    } finally { await cleanup(b); }
  });

  it('generation: 16 hex de sha256(passphraseHash + jwtSecret)', () => {
    const g = generation({ passphraseHash: passHash(), jwtSecret: SECRET });
    expect(g).toMatch(/^[0-9a-f]{16}$/);
    expect(g).not.toBe(generation({ passphraseHash: passHash(), jwtSecret: SECRET + 'x' }));
    expect(g).not.toBe(generation({ passphraseHash: passHash() + 'x', jwtSecret: SECRET }));
  });

  it('o access token carrega gen e fid', async () => {
    const a = await startApp();
    const { tokens } = await fullLogin(a);
    const payload = JSON.parse(Buffer.from(tokens.access_token.split('.')[1], 'base64url').toString());
    expect(payload.gen).toBe(generation(a.cfg));
    expect(typeof payload.fid).toBe('string');
    expect(payload.fid.length).toBeGreaterThan(10);
    await cleanup(a);
  });

  it('/revoke de um refresh token derruba também os access tokens da família (e persiste)', async () => {
    const a = await startApp();
    const one = await fullLogin(a);
    const two = await fullLogin(a); // outra família: não é afetada
    expect((await mcp(a, one.tokens.access_token)).status).toBe(200);
    expect((await revoke(a, one.tokens.refresh_token)).status).toBe(200);
    expect((await mcp(a, one.tokens.access_token)).status).toBe(401);
    expect((await mcp(a, two.tokens.access_token)).status).toBe(200);
    // sobrevive a reinício
    const b = await a.restart();
    try {
      expect((await mcp(b, one.tokens.access_token)).status).toBe(401);
      expect((await mcp(b, two.tokens.access_token)).status).toBe(200);
      const raw = readFileSync(join(b.dataDir, 'revoked.json'), 'utf8');
      expect(raw).not.toContain(one.tokens.refresh_token);
    } finally { await cleanup(b); }
  });

  it('reuso de refresh token (roubo) também derruba os access tokens da família', async () => {
    const a = await startApp();
    const { clientId, tokens } = await fullLogin(a);
    const r1 = await refresh(a, clientId, tokens.refresh_token);
    expect((await mcp(a, r1.body.access_token)).status).toBe(200);
    expect((await refresh(a, clientId, tokens.refresh_token)).body.error).toBe('invalid_grant'); // reuso
    expect((await mcp(a, r1.body.access_token)).status).toBe(401);
    expect((await mcp(a, tokens.access_token)).status).toBe(401);
    await cleanup(a);
  });

  describe('lista de bloqueio de famílias (store)', () => {
    const mk = (t: { v: number }, dir: string) => new OAuthStore(dir, () => new Date(t.v), 'gen-teste');
    it('entradas expiram em 1 h, são persistidas e a lista é limitada', () => {
      const dir = mkdtempSync(join(tmpdir(), 'mcp-store-'));
      try {
        const t = { v: 1_000_000 };
        const st = mk(t, dir);
        st.revokeFamily('fam-a');
        expect(st.isFamilyRevoked('fam-a')).toBe(true);
        expect(st.isFamilyRevoked('fam-b')).toBe(false);
        expect(mk(t, dir).isFamilyRevoked('fam-a')).toBe(true); // recarrega do disco
        t.v += REVOKED_TTL_MS - 1;
        expect(st.isFamilyRevoked('fam-a')).toBe(true);
        t.v += 2;
        expect(st.isFamilyRevoked('fam-a')).toBe(false);
        expect(mk(t, dir).isFamilyRevoked('fam-a')).toBe(false);
        for (let i = 0; i < 300; i++) st.revokeFamily(`f${i}`);
        const saved = JSON.parse(readFileSync(join(dir, 'revoked.json'), 'utf8')) as unknown[];
        expect(saved.length).toBeLessThanOrEqual(200);
        expect(st.isFamilyRevoked('f299')).toBe(true);
      } finally { rmSync(dir, { recursive: true, force: true }); }
    });
    it('refresh.json antigo, sem gen/familyExpiresAt, é ignorado (exige novo login)', () => {
      const dir = mkdtempSync(join(tmpdir(), 'mcp-store-'));
      try {
        writeFileSync(join(dir, 'refresh.json'), JSON.stringify([
          { hash: 'h', family: 'f', clientId: 'c', expiresAt: Date.now() + 1e9, status: 'active' },
        ]));
        const st = new OAuthStore(dir, () => new Date(), 'gen-teste');
        expect(st.rotateRefresh('qualquer', 'c')).toBeNull();
      } finally { rmSync(dir, { recursive: true, force: true }); }
    });
  });
});

describe('HitLimiter', () => {
  it('janela deslizante por chave', () => {
    let t = 0;
    const h = new HitLimiter(() => new Date(t), 2, 1000);
    expect(h.allow('a')).toBe(true);
    expect(h.allow('a')).toBe(true);
    expect(h.allow('a')).toBe(false);
    expect(h.allow('b')).toBe(true);
    t += 1001;
    expect(h.allow('a')).toBe(true);
  });
});
