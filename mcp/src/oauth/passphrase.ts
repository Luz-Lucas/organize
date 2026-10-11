import { randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';

const N = 2 ** 15;
const R = 8;
const P = 1;
const KEYLEN = 32;
// N=2^15, r=8 exige ~32 MiB; o padrão do Node (32 MiB) é justo demais.
const MAXMEM = 128 * 1024 * 1024;

/** Gera `scrypt$<saltHex>$<hashHex>`. */
export function hashPassphrase(pass: string): string {
  const salt = randomBytes(16);
  const hash = scryptSync(pass, salt, KEYLEN, { N, r: R, p: P, maxmem: MAXMEM });
  return `scrypt$${salt.toString('hex')}$${hash.toString('hex')}`;
}

/** Confere em tempo constante. Nunca lança: formato inválido => false. */
export function verifyPassphrase(pass: string, stored: string): boolean {
  try {
    const parts = stored.split('$');
    if (parts.length !== 3 || parts[0] !== 'scrypt') return false;
    const [, saltHex, hashHex] = parts;
    if (!/^[0-9a-f]{16,128}$/i.test(saltHex) || saltHex.length % 2 !== 0) return false;
    if (!/^[0-9a-f]{64}$/i.test(hashHex)) return false; // tamanho fixo: truncar não pode validar
    const expected = Buffer.from(hashHex, 'hex');
    const actual = scryptSync(pass, Buffer.from(saltHex, 'hex'), KEYLEN, { N, r: R, p: P, maxmem: MAXMEM });
    return actual.length === expected.length && timingSafeEqual(actual, expected);
  } catch {
    return false;
  }
}
