import { describe, expect, it } from 'vitest';
import { hashPassphrase, verifyPassphrase } from '../src/oauth/passphrase.js';
import { verifyS256 } from '../src/oauth/pkce.js';
import { createHash } from 'node:crypto';

describe('passphrase', () => {
  const h = hashPassphrase('uma senha longa');
  it('ida e volta e formato scrypt$salt$hash', () => {
    expect(h).toMatch(/^scrypt\$[0-9a-f]{32}\$[0-9a-f]{64}$/);
    expect(verifyPassphrase('uma senha longa', h)).toBe(true);
  });
  it('sal aleatório: dois hashes da mesma senha diferem', () => {
    expect(hashPassphrase('uma senha longa')).not.toBe(h);
  });
  it('senha errada é falsa', () => {
    expect(verifyPassphrase('outra', h)).toBe(false);
    expect(verifyPassphrase('', h)).toBe(false);
  });
  it('hash malformado é falso e nunca lança', () => {
    for (const bad of ['', 'x', 'scrypt$', 'scrypt$zz$zz', 'bcrypt$aa$bb', 'scrypt$aa$bb$cc', 'scrypt$' + 'a'.repeat(32) + '$abc', h.slice(0, -2)]) {
      expect(verifyPassphrase('uma senha longa', bad)).toBe(false);
    }
  });
});

describe('pkce', () => {
  const verifier = 'a'.repeat(50);
  const challenge = createHash('sha256').update(verifier).digest('base64url');
  it('aceita o par correto e recusa o resto', () => {
    expect(verifyS256(verifier, challenge)).toBe(true);
    expect(verifyS256('b'.repeat(50), challenge)).toBe(false);
    expect(verifyS256('curto', challenge)).toBe(false);
    expect(verifyS256(verifier, verifier)).toBe(false); // método plain não passa
    expect(verifyS256(verifier, '')).toBe(false);
  });
});
