import { createHash, timingSafeEqual } from 'node:crypto';

/** code_verifier conforme RFC 7636 §4.1. */
export const VERIFIER_RE = /^[A-Za-z0-9\-._~]{43,128}$/;
/** code_challenge S256 = base64url(sha256) sem padding = 43 caracteres. */
export const CHALLENGE_RE = /^[A-Za-z0-9_-]{43}$/;

export function verifyS256(verifier: string, challenge: string): boolean {
  if (!VERIFIER_RE.test(verifier) || !CHALLENGE_RE.test(challenge)) return false;
  const computed = Buffer.from(createHash('sha256').update(verifier).digest('base64url'));
  const expected = Buffer.from(challenge);
  return computed.length === expected.length && timingSafeEqual(computed, expected);
}
