import { randomBytes } from 'node:crypto';
import { jwtVerify, SignJWT } from 'jose';
import type { McpConfig } from '../config.js';

export const ACCESS_TTL_SECONDS = 3600;

type TokenCfg = Pick<McpConfig, 'jwtSecret' | 'publicUrl' | 'userId'>;

const key = (cfg: TokenCfg) => new TextEncoder().encode(cfg.jwtSecret);
export const audience = (cfg: Pick<McpConfig, 'publicUrl'>) => `${cfg.publicUrl}/mcp`;

export async function signAccessToken(cfg: TokenCfg, now: Date): Promise<string> {
  const iat = Math.floor(now.getTime() / 1000);
  return new SignJWT({})
    .setProtectedHeader({ alg: 'HS256', typ: 'at+jwt' })
    .setIssuer(cfg.publicUrl)
    .setAudience(audience(cfg))
    .setSubject(cfg.userId)
    .setIssuedAt(iat)
    .setExpirationTime(iat + ACCESS_TTL_SECONDS)
    .setJti(randomBytes(12).toString('base64url'))
    .sign(key(cfg));
}

/** true somente se assinatura, exp, iss, aud e sub conferem. Nunca lança. */
export async function verifyAccessToken(cfg: TokenCfg, token: string, now: Date): Promise<boolean> {
  try {
    await jwtVerify(token, key(cfg), {
      algorithms: ['HS256'],
      issuer: cfg.publicUrl,
      audience: audience(cfg),
      subject: cfg.userId,
      requiredClaims: ['exp', 'iss', 'aud', 'sub'],
      currentDate: now,
    });
    return true;
  } catch {
    return false;
  }
}
