import { createHash, randomBytes } from 'node:crypto';
import { jwtVerify, SignJWT } from 'jose';
import type { McpConfig } from '../config.js';

export const ACCESS_TTL_SECONDS = 3600;

type TokenCfg = Pick<McpConfig, 'jwtSecret' | 'publicUrl' | 'userId' | 'passphraseHash'>;

/**
 * "Geração" das credenciais: 16 primeiros hex de sha256(passphraseHash + jwtSecret). Todo access/refresh token
 * carrega a geração em que nasceu; trocar a senha ou o segredo muda a geração e invalida tudo.
 */
export function generation(cfg: Pick<McpConfig, 'passphraseHash' | 'jwtSecret'>): string {
  return createHash('sha256').update(cfg.passphraseHash + cfg.jwtSecret).digest('hex').slice(0, 16);
}

const key = (cfg: TokenCfg) => new TextEncoder().encode(cfg.jwtSecret);
export const audience = (cfg: Pick<McpConfig, 'publicUrl'>) => `${cfg.publicUrl}/mcp`;

/** `familyId` entra no claim `fid`, para a revogação de uma família barrar também os access tokens dela. */
export async function signAccessToken(cfg: TokenCfg, now: Date, familyId: string): Promise<string> {
  const iat = Math.floor(now.getTime() / 1000);
  return new SignJWT({ gen: generation(cfg), fid: familyId })
    .setProtectedHeader({ alg: 'HS256', typ: 'at+jwt' })
    .setIssuer(cfg.publicUrl)
    .setAudience(audience(cfg))
    .setSubject(cfg.userId)
    .setIssuedAt(iat)
    .setExpirationTime(iat + ACCESS_TTL_SECONDS)
    .setJti(randomBytes(12).toString('base64url'))
    .sign(key(cfg));
}

/** Devolve o `fid` somente se assinatura, exp, iss, aud, sub e geração conferem. Nunca lança. */
export async function verifyAccessToken(cfg: TokenCfg, token: string, now: Date): Promise<{ fid: string } | null> {
  try {
    const { payload } = await jwtVerify(token, key(cfg), {
      algorithms: ['HS256'],
      issuer: cfg.publicUrl,
      audience: audience(cfg),
      subject: cfg.userId,
      requiredClaims: ['exp', 'iss', 'aud', 'sub', 'gen', 'fid'],
      currentDate: now,
    });
    if (payload.gen !== generation(cfg) || typeof payload.fid !== 'string' || !payload.fid) return null;
    return { fid: payload.fid };
  } catch {
    return null;
  }
}
