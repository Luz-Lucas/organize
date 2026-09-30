export interface Config {
  supabaseUrl: string;
  serviceKey: string;
  userId: string;
  timeZone: string;
  port: number;
  allowedAlexaUserId: string | null;
  cookieFile: string;
  amazonPage: string;
  alexaServiceHost: string;
  loginProxyPort: number;
}

export function loadConfig(env: Record<string, string | undefined>): Config {
  const need = (key: string) => {
    const v = env[key]?.trim();
    if (!v) throw new Error(`variável ${key} obrigatória`);
    return v;
  };
  const opt = (key: string, fallback: string) => env[key]?.trim() || fallback;
  return {
    supabaseUrl: need('SUPABASE_URL'),
    serviceKey: need('SUPABASE_SERVICE_ROLE_KEY'),
    userId: need('ORGANIZACIONAL_USER_ID'),
    timeZone: opt('TZ_NAME', 'America/Sao_Paulo'),
    port: Number(opt('PORT', '8080')),
    allowedAlexaUserId: env.ALEXA_ALLOWED_USER_ID?.trim() || null,
    cookieFile: opt('ALEXA_COOKIE_FILE', '/data/alexa-cookie.json'),
    amazonPage: opt('AMAZON_PAGE', 'amazon.com.br'),
    alexaServiceHost: opt('ALEXA_SERVICE_HOST', 'alexa.amazon.com.br'),
    loginProxyPort: Number(opt('LOGIN_PROXY_PORT', '3001')),
  };
}
