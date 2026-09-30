import { writeFile } from 'node:fs/promises';
import { AlexaRemoteGateway } from '../alexa-remote-gateway.js';
import { loadConfig } from '../config.js';

const cfg = loadConfig(process.env);
const gw = await AlexaRemoteGateway.connect({
  cookieFile: cfg.cookieFile, amazonPage: cfg.amazonPage, alexaServiceHost: cfg.alexaServiceHost, language: 'pt-BR',
});
const echos = await gw.listEchos();
console.log('Echos:', echos);
console.log('Dispositivos:', await gw.listSmartDevices());
console.log('Rotinas:', await gw.listRoutines());
const [flag, device, ...words] = process.argv.slice(2);
if (flag === '--speak' && device) {
  await gw.speak(device, words.join(' ') || 'Teste da ponte Organizacional.');
  console.log('Falou.');
}
await writeFile('/data/smoke-ok.txt', new Date().toISOString());
process.exit(0);
