import { chunkSpeech } from './briefing.js';
import type { AlexaGateway, DeviceAction } from './gateway.js';

export type CommandKind = 'device' | 'routine' | 'speak' | 'music' | 'sync' | 'wake_test' | 'delete_device';

export interface Command {
  id: string;
  kind: CommandKind;
  payload: Record<string, unknown>;
  createdAt: Date;
}

export class CommandError extends Error {}

export const COMMAND_MAX_AGE_MS = 120_000;

export const isExpired = (cmd: Command, now: Date, maxAgeMs = COMMAND_MAX_AGE_MS) =>
  now.getTime() - cmd.createdAt.getTime() > maxAgeMs;

export interface CommandDeps {
  gateway: AlexaGateway;
  sync: () => Promise<void>;
  wakeTest: (planId: string) => Promise<string>;
}

const DEVICE_ACTIONS: DeviceAction[] = ['turnOn', 'turnOff', 'setBrightness'];

function str(payload: Record<string, unknown>, key: string): string {
  const v = payload[key];
  if (typeof v !== 'string' || !v.trim()) throw new CommandError(`campo "${key}" ausente`);
  return v;
}

export async function executeCommand(cmd: Command, deps: CommandDeps): Promise<string> {
  const p = cmd.payload;
  switch (cmd.kind) {
    case 'device': {
      const action = str(p, 'action');
      if (!DEVICE_ACTIONS.includes(action as DeviceAction)) throw new CommandError(`ação desconhecida: ${action}`);
      let brightness: number | undefined;
      if (action === 'setBrightness') {
        brightness = Number(p.brightness);
        if (!Number.isInteger(brightness) || brightness < 0 || brightness > 100) {
          throw new CommandError('brilho deve ser de 0 a 100');
        }
      }
      await deps.gateway.deviceAction(str(p, 'entityId'), action as DeviceAction, brightness);
      return 'ok';
    }
    case 'routine':
      await deps.gateway.runRoutine(str(p, 'routineId'), str(p, 'echoDeviceId'));
      return 'ok';
    case 'speak': {
      const echo = str(p, 'echoDeviceId');
      for (const chunk of chunkSpeech(str(p, 'text'))) await deps.gateway.speak(echo, chunk);
      return 'ok';
    }
    case 'music':
      await deps.gateway.playSpotify(str(p, 'echoDeviceId'), str(p, 'query'));
      return 'ok';
    case 'delete_device':
      await deps.gateway.deleteSmartDevice(str(p, 'entityId'));
      // O dispositivo já saiu da Amazon (irreversível): uma falha só na
      // ressincronização não pode fazer o comando parecer que falhou.
      try {
        await deps.sync();
      } catch {
        return 'ok (removido; a lista será atualizada na próxima sincronização)';
      }
      return 'ok';
    case 'sync':
      await deps.sync();
      return 'ok';
    case 'wake_test':
      return deps.wakeTest(str(p, 'planId'));
    default:
      throw new CommandError(`tipo desconhecido: ${String(cmd.kind)}`);
  }
}
