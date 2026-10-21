import type { AddressInfo } from 'node:net';
import { ExpressAdapter } from 'ask-sdk-express-adapter';
import express from 'express';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildSkill } from '../src/skill.js';

describe('ExpressAdapter', () => {
  const app = express();
  const skill = buildSkill({ allowedUserId: 'u', log: () => {}, timeZone: 'America/Sao_Paulo', addTask: async () => { throw new Error('não deve ser chamado'); } });
  const adapter = new ExpressAdapter(skill, true, true);
  app.post('/alexa', adapter.getRequestHandlers());
  const server = app.listen(0);
  beforeAll(() => new Promise<void>((r) => (server.listening ? r() : server.once('listening', () => r()))));
  afterAll(() => new Promise<void>((r) => server.close(() => r())));

  it('rejeita requisição sem assinatura válida da Alexa', async () => {
    const { port } = server.address() as AddressInfo;
    const res = await fetch(`http://127.0.0.1:${port}/alexa`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ version: '1.0', request: { type: 'LaunchRequest', timestamp: new Date().toISOString() } }),
    });
    expect(res.status).not.toBe(200);
    expect(res.status).toBeGreaterThanOrEqual(400);
  });
});
