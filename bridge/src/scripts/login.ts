import { writeFile } from 'node:fs/promises';
import AlexaRemote from 'alexa-remote2';
import { loadConfig } from '../config.js';

const cfg = loadConfig(process.env);
const alexa = new AlexaRemote();

console.log(`Abra http://localhost:${cfg.loginProxyPort} (pelo túnel SSH) e entre na sua conta Amazon.`);
alexa.on('cookie', async () => {
  await writeFile(cfg.cookieFile, JSON.stringify(alexa.cookieData));
  console.log(`Login salvo em ${cfg.cookieFile}. Reinicie a ponte: docker compose restart bridge`);
  process.exit(0);
});
alexa.init({
  proxyOnly: true,
  proxyOwnIp: 'localhost',
  proxyPort: cfg.loginProxyPort,
  proxyListenBind: '0.0.0.0',
  amazonPage: cfg.amazonPage,
  alexaServiceHost: cfg.alexaServiceHost,
  acceptLanguage: 'pt-BR',
  amazonPageProxyLanguage: 'pt_BR',
  useWsMqtt: false,
  logger: (msg: string) => console.log(msg),
} as Record<string, unknown>, (err: unknown) => {
  if (err) console.log(String((err as Error).message ?? err));
});
