import { describe, expect, it } from 'vitest';
import { loadConfig } from '../src/config.js';

const base = {
  SUPABASE_URL: 'https://x.supabase.co',
  SUPABASE_SERVICE_ROLE_KEY: 'k',
  ORGANIZACIONAL_USER_ID: 'u',
};

describe('loadConfig', () => {
  it('aplica os padrões do Brasil', () => {
    const cfg = loadConfig(base);
    expect(cfg.timeZone).toBe('America/Sao_Paulo');
    expect(cfg.amazonPage).toBe('amazon.com.br');
    expect(cfg.alexaServiceHost).toBe('alexa.amazon.com.br');
    expect(cfg.port).toBe(8080);
    expect(cfg.allowedAlexaUserId).toBeNull();
    expect(cfg.cookieFile).toBe('/data/alexa-cookie.json');
  });

  it('falha com mensagem clara quando falta variável', () => {
    expect(() => loadConfig({ ...base, SUPABASE_SERVICE_ROLE_KEY: ' ' })).toThrow(
      'variável SUPABASE_SERVICE_ROLE_KEY obrigatória',
    );
  });
});
