import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { cleanup, fullLogin, startApp, type TestApp } from './oauth-helpers.js';

let app: TestApp;
beforeAll(async () => { app = await startApp(); });
afterAll(async () => { await cleanup(app); });

describe('/mcp com o cliente MCP do SDK', () => {
  it('fluxo OAuth completo e tools/list + tools/call pelo transporte HTTP', async () => {
    const { tokens } = await fullLogin(app);
    const client = new Client({ name: 'teste', version: '1.0.0' });
    const transport = new StreamableHTTPClientTransport(new URL(`${app.url}/mcp`), {
      requestInit: { headers: { Authorization: `Bearer ${tokens.access_token}` } },
    });
    await client.connect(transport);
    const list = await client.listTools();
    expect(list.tools.map((t) => t.name)).toContain('ping');
    const res = await client.callTool({ name: 'ping', arguments: {} });
    expect(JSON.stringify(res.content)).toContain('pong');
    // requisições seguintes (sem sessão) continuam funcionando
    expect((await client.listTools()).tools.length).toBeGreaterThan(0);
    await client.close();
  });

  it('JSON inválido => 400 sem vazar detalhes', async () => {
    const { tokens } = await fullLogin(app);
    const r = await fetch(`${app.url}/mcp`, {
      method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${tokens.access_token}` }, body: '{quebrado',
    });
    expect(r.status).toBe(400);
    expect(await r.text()).not.toMatch(/SyntaxError|at /);
  });

  it('corpo acima de 1 MB é recusado', async () => {
    const { tokens } = await fullLogin(app);
    const r = await fetch(`${app.url}/mcp`, {
      method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${tokens.access_token}` },
      body: JSON.stringify({ x: 'a'.repeat(1_100_000) }),
    });
    expect(r.status).toBe(413);
  });
});
