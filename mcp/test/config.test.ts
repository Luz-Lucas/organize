import { describe, expect, it } from 'vitest';
import { loadConfig } from '../src/config.js';

const base = {
  MCP_PUBLIC_URL: 'https://x.example', MCP_JWT_SECRET: 'x'.repeat(40), MCP_PASSPHRASE_HASH: 'scrypt$aa$bb',
  SUPABASE_URL: 'http://x', SUPABASE_SERVICE_ROLE_KEY: 'k', ORGANIZACIONAL_USER_ID: 'u',
};
const matches = (patterns: RegExp[], uri: string) => patterns.some((re) => re.test(uri));

describe('allowedRedirects padrão (ancorados)', () => {
  const { allowedRedirects } = loadConfig(base);

  it('aceita exatamente os retornos do Claude e loopback', () => {
    for (const ok of [
      'https://claude.ai/api/mcp/auth_callback', 'https://claude.com/api/mcp/auth_callback',
      'http://localhost:6274/cb', 'http://127.0.0.1/cb', 'http://localhost/x/y',
    ]) expect(matches(allowedRedirects, ok), ok).toBe(true);
  });

  it('todo padrão padrão começa com ^ e termina com $', () => {
    for (const re of allowedRedirects) {
      expect(re.source.startsWith('^'), re.source).toBe(true);
      expect(re.source.endsWith('$'), re.source).toBe(true);
    }
  });

  it('não casa por prefixo, sufixo ou embutido em outra URL', () => {
    for (const bad of [
      'https://claude.ai/api/mcp/auth_callbackX', 'https://claude.ai/api/mcp/auth_callback/', 'xhttps://claude.ai/api/mcp/auth_callback',
      'https://evil.example/?u=https://claude.ai/api/mcp/auth_callback', 'https://claude.ai.evil.example/api/mcp/auth_callback',
      'https://evilclaude.ai/api/mcp/auth_callback', 'http://claude.ai/api/mcp/auth_callback',
      'https://claude.ai/api/mcp/auth_callback\nhttps://evil.example', 'https://claude.ai/api/mcp/auth_callback?x=1',
      'http://localhost.evil.example/cb', 'http://localhost@evil.example/cb', 'http://localhostevil/cb',
      'http://127.0.0.1.evil.example/cb', 'https://localhost/cb', 'http://localhost:abc/cb', 'http://evil.example/http://localhost/cb',
    ]) expect(matches(allowedRedirects, bad), JSON.stringify(bad)).toBe(false);
  });

  it('padrões extras de MCP_ALLOWED_REDIRECTS são compilados como escritos (quem os define deve ancorá-los)', () => {
    const cfg = loadConfig({ ...base, MCP_ALLOWED_REDIRECTS: '^https://app\\.example/cb$, https://solto\\.example' });
    expect(cfg.allowedRedirects).toHaveLength(allowedRedirects.length + 2);
    expect(matches(cfg.allowedRedirects, 'https://app.example/cb')).toBe(true);
    expect(matches(cfg.allowedRedirects, 'https://app.example/cb2')).toBe(false);
    // sem âncoras o padrão casa por substring: por isso o README manda ancorar
    expect(matches(cfg.allowedRedirects, 'https://evil.example/?https://solto.example')).toBe(true);
  });
});
