export interface McpConfig {
  port: number;
  /** URL pública SEM barra final, ex.: https://seu-dominio.duckdns.org */
  publicUrl: string;
  supabaseUrl: string;
  serviceKey: string;
  userId: string;
  /** Segredo (>= 32 caracteres) que assina os tokens de acesso. */
  jwtSecret: string;
  /** Hash scrypt da senha de acesso: `scrypt$<saltHex>$<hashHex>` (veja scripts/set-passphrase.ts). */
  passphraseHash: string;
  /** Pasta persistente (clientes OAuth registrados e refresh tokens). */
  dataDir: string;
  timeZone: string;
  /** Padrões aceitos para redirect_uri no registro dinâmico de clientes. */
  allowedRedirects: RegExp[];
}

const DEFAULT_REDIRECTS = [
  '^https://claude\\.ai/api/mcp/auth_callback$',
  '^https://claude\\.com/api/mcp/auth_callback$',
  '^http://(localhost|127\\.0\\.0\\.1)(:\\d+)?/.*$',
];

function need(env: Record<string, string | undefined>, key: string): string {
  const v = env[key]?.trim();
  if (!v) throw new Error(`variável ${key} ausente`);
  return v;
}

export function loadConfig(env: Record<string, string | undefined>): McpConfig {
  const jwtSecret = need(env, 'MCP_JWT_SECRET');
  if (jwtSecret.length < 32) throw new Error('MCP_JWT_SECRET precisa de pelo menos 32 caracteres');
  const extra = (env.MCP_ALLOWED_REDIRECTS ?? '').split(',').map((s) => s.trim()).filter(Boolean);
  return {
    port: Number(env.MCP_PORT ?? 8081),
    publicUrl: need(env, 'MCP_PUBLIC_URL').replace(/\/+$/, ''),
    supabaseUrl: need(env, 'SUPABASE_URL'),
    serviceKey: need(env, 'SUPABASE_SERVICE_ROLE_KEY'),
    userId: need(env, 'ORGANIZACIONAL_USER_ID'),
    jwtSecret,
    passphraseHash: need(env, 'MCP_PASSPHRASE_HASH'),
    dataDir: env.MCP_DATA_DIR ?? '/data',
    timeZone: env.TZ_NAME ?? 'America/Sao_Paulo',
    allowedRedirects: [...DEFAULT_REDIRECTS, ...extra].map((p) => new RegExp(p)),
  };
}
