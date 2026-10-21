import { createClient } from '@supabase/supabase-js';
import expressAdapter from 'ask-sdk-express-adapter';
import express from 'express';
import { AlexaRemoteGateway } from './alexa-remote-gateway.js';
import { wakeTexts } from './briefing.js';
import { CommandError, executeCommand, isExpired, type Command } from './commands.js';
import { loadConfig } from './config.js';
import { AlexaAuthError, type AlexaGateway } from './gateway.js';
import { createOverridesLoader } from './overrides-loader.js';
import { planWakeActions } from './scheduler.js';
import { fetchWeather, reverseCity, weatherText } from './weather.js';
import { buildSkill } from './skill.js';
import { SupabaseStore } from './supabase-store.js';
import { addDays, localParts, timeZoneMatches } from './time.js';
import { applyWakeActions, runWake, testPlan, weatherSpeech, type PresenceSource } from './wake.js';

const { ExpressAdapter } = expressAdapter;
const cfg = loadConfig(process.env);
const log = (m: string) => console.log(`[${new Date().toISOString()}] ${m}`);
const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

if (!timeZoneMatches(new Date(), cfg.timeZone)) {
  console.error(`O fuso do processo difere de ${cfg.timeZone}. Defina TZ=${cfg.timeZone}: os alarmes da Alexa usam o horário local do processo.`);
  process.exit(1);
}

process.on('unhandledRejection', (reason) => log(`rejeição não tratada: ${String((reason as Error)?.message ?? reason)}`));

const db = createClient(cfg.supabaseUrl, cfg.serviceKey, { auth: { persistSession: false } });
const store = new SupabaseStore(db, cfg.userId, log);
const overridesFor = createOverridesLoader((from, to) => store.loadOverrides(from, to), log);
const briefingInput = () => store.briefingInput(new Date(), cfg.timeZone);

/** Texto falado do clima para um ponto; falhas viram null (o despertar segue sem clima). Não registra coordenadas; só coordenadas arredondadas (~1 km) saem da ponte. */
async function weatherAt(at: { lat: number; lon: number }): Promise<string | null> {
  const w = await fetchWeather(at.lat, at.lon, { fetch }, cfg.timeZone);
  if (!w) return null;
  const city = await reverseCity(at.lat, at.lon, { fetch });
  return weatherText({ city, w });
}

// Parte oficial: sobe mesmo se a parte não oficial estiver sem login.
const app = express();
const skill = buildSkill({
  allowedUserId: cfg.allowedAlexaUserId, log,
  timeZone: cfg.timeZone,
  addTask: (task) => store.addTask(task),
});
app.post('/alexa', new ExpressAdapter(skill, true, true).getRequestHandlers());
app.get('/health', (_req, res) => { res.json({ ok: true }); });
app.listen(cfg.port, () => log(`ouvindo na porta ${cfg.port}`));

// Parte não oficial
let gateway: AlexaGateway | null = null;
let nextConnectAt = 0;
const inFlight = new Set<string>();
const processing = new Set<string>();

async function handleError(e: unknown, context: string): Promise<void> {
  if (e instanceof AlexaAuthError) {
    gateway = null;
    nextConnectAt = Date.now() + 5 * 60_000;
    await store.setStatus('auth_required', e.message).catch(() => {});
    log(`login da Alexa necessário (${context}): ${e.message}`);
  } else {
    log(`erro em ${context}: ${(e as Error).message}`);
  }
}

async function sync(): Promise<void> {
  if (!gateway) throw new CommandError('ponte sem login na Alexa');
  const [echos, smart, routines] = await Promise.all([
    gateway.listEchos(), gateway.listSmartDevices(), gateway.listRoutines(),
  ]);
  await store.saveDevices(echos, smart);
  await store.saveRoutines(routines);
  log(`sincronizado: ${echos.length} Echos, ${smart.length} dispositivos, ${routines.length} rotinas`);
}

async function ensureGateway(): Promise<AlexaGateway | null> {
  if (gateway || Date.now() < nextConnectAt) return gateway;
  try {
    gateway = await AlexaRemoteGateway.connect({
      cookieFile: cfg.cookieFile, amazonPage: cfg.amazonPage,
      alexaServiceHost: cfg.alexaServiceHost, language: 'pt-BR', log,
    });
    await store.setStatus('ok', null);
    await sync();
  } catch (e) {
    if (!(e instanceof AlexaAuthError)) {
      nextConnectAt = Date.now() + 60_000;
      await store.setStatus('error', (e as Error).message).catch(() => {});
    }
    await handleError(e, 'conexão');
  }
  return gateway;
}

async function wakeTest(planId: string): Promise<string> {
  const plan = (await store.listWakePlans()).find((p) => p.id === planId);
  if (!plan) throw new CommandError('despertar não encontrado');
  if (!gateway) throw new CommandError('ponte sem login na Alexa');
  // "Testar agora" ignora a presença, mas fala o clima e executa as ações de dispositivos.
  let source: PresenceSource | null = null;
  if (plan.includeWeather) source = await store.loadPresenceInput().catch(() => null);
  const weather = await weatherSpeech(plan, source, { weather: weatherAt, log });
  const result = await runWake(testPlan(plan), wakeTexts(await briefingInput(), weather), gateway, sleep);
  return result.ok ? 'ok' : `falhou: ${result.notes.join('; ')}`;
}

async function processCommand(cmd: Command): Promise<void> {
  if (processing.has(cmd.id)) return;
  processing.add(cmd.id);
  try {
    if (isExpired(cmd, new Date())) {
      await store.finishCommand(cmd.id, 'expired', 'comando antigo demais; não executado');
      return;
    }
    if (!(await store.claimCommand(cmd.id))) return;
    const gw = await ensureGateway();
    if (!gw) {
      await store.finishCommand(cmd.id, 'failed', 'ponte sem login na Alexa');
      return;
    }
    try {
      await store.finishCommand(cmd.id, 'done', await executeCommand(cmd, { gateway: gw, sync, wakeTest }));
    } catch (e) {
      await handleError(e, `comando ${cmd.kind}`);
      await store.finishCommand(cmd.id, 'failed', (e as Error).message);
    }
  } catch (e) {
    log(`erro ao processar comando ${cmd.id}: ${(e as Error).message}`);
  } finally {
    processing.delete(cmd.id);
  }
}

let lastOverridePurge = 0;

/** Limpa exceções com mais de 7 dias, no máximo uma vez por hora; falhas só entram no log. */
async function purgeOverridesHourly(today: string): Promise<void> {
  if (Date.now() - lastOverridePurge < 60 * 60_000) return;
  lastOverridePurge = Date.now();
  try {
    await store.purgeOldOverrides(addDays(today, -7));
  } catch (e) {
    log(`limpeza de exceções de despertar: ${(e as Error).message}`);
  }
}

async function wakeTick(): Promise<void> {
  try {
    const now = new Date();
    const today = localParts(now, cfg.timeZone).date;
    const plans = await store.listWakePlans();
    const runs = await store.listWakeRuns(addDays(today, -2));
    const overrides = await overridesFor(today);
    void purgeOverridesHourly(today);
    const actions = planWakeActions(plans, runs, now, cfg.timeZone, undefined, overrides);
    if (actions.length === 0) return;
    const gw = await ensureGateway();
    if (!gw) return; // sem login: o alarme reserva já armado toca sozinho
    const running = await applyWakeActions(actions, {
      gateway: gw, store, sleep, log,
      briefing: async (weather) => wakeTexts(await briefingInput(), weather),
      presence: () => store.loadPresenceInput(),
      weather: weatherAt,
    }, inFlight);
    // Cada despertar roda em segundo plano; AlexaAuthError vira status auth_required, sem rejeição solta.
    void Promise.allSettled(running).then(async (results) => {
      for (const r of results) if (r.status === 'rejected') await handleError(r.reason, 'despertar');
    });
  } catch (e) {
    await handleError(e, 'despertador');
  }
}

void store.sweepStuckCommands().then((n) => { if (n > 0) log(`${n} comando(s) preso(s) em execução marcados como falhos`); })
  .catch((e) => log(`varredura de comandos presos: ${e.message}`));
store.onNewCommand((cmd) => void processCommand(cmd));
setInterval(() => void store.pendingCommands().then((cmds) => cmds.forEach((c) => void processCommand(c))).catch((e) => log(`fila: ${e.message}`)), 15_000);
setInterval(() => void store.heartbeat().catch((e) => log(`heartbeat: ${e.message}`)), 60_000);
setInterval(() => void (async () => { if (await ensureGateway()) await sync().catch((e) => handleError(e, 'sincronização')); })(), 10 * 60_000);
setInterval(() => void wakeTick(), 30_000);
void ensureGateway().then(() => wakeTick());
