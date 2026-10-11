// Gera o hash da senha de acesso do MCP. Roda na VM:
//   docker compose run --rm -it mcp node dist/scripts/set-passphrase.js
// Imprime SOMENTE a linha MCP_PASSPHRASE_HASH=... (nunca a senha).
import { hashPassphrase } from '../oauth/passphrase.js';

function askHidden(prompt: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const stdin = process.stdin;
    if (!stdin.isTTY || typeof stdin.setRawMode !== 'function') {
      reject(new Error('Precisa de um terminal interativo (use -it).'));
      return;
    }
    process.stderr.write(prompt);
    let buf = '';
    stdin.setRawMode(true);
    stdin.resume();
    stdin.setEncoding('utf8');
    const done = (err?: Error) => {
      stdin.setRawMode(false);
      stdin.pause();
      stdin.removeListener('data', onData);
      process.stderr.write('\n');
      if (err) reject(err); else resolve(buf);
    };
    const onData = (chunk: string) => {
      for (const ch of chunk) {
        if (ch === '\r' || ch === '\n' || ch === '\u0004') return done();
        if (ch === '\u0003') return done(new Error('Cancelado.'));
        if (ch === '\u007f' || ch === '\b') buf = buf.slice(0, -1);
        else if (ch >= ' ') buf += ch;
      }
    };
    stdin.on('data', onData);
  });
}

async function main(): Promise<void> {
  const a = await askHidden('Nova senha de acesso (mín. 12 caracteres): ');
  if (a.length < 12) throw new Error('A senha precisa ter pelo menos 12 caracteres.');
  const b = await askHidden('Repita a senha: ');
  if (a !== b) throw new Error('As senhas não conferem.');
  // Aspas simples: o docker compose interpreta $ nos arquivos env_file.
  console.log(`MCP_PASSPHRASE_HASH='${hashPassphrase(a)}'`);
}

main().catch((e: Error) => {
  console.error(e.message);
  process.exit(1);
});
