export type DeviceAction = 'turnOn' | 'turnOff' | 'setBrightness';

export interface EchoDevice { id: string; name: string; online: boolean }
export interface SmartDevice { id: string; name: string; operations: string[] }
export interface Routine { id: string; name: string }

/** Login da Alexa inválido/expirado: a ponte precisa de `npm run login`. */
export class AlexaAuthError extends Error {}

export interface AlexaGateway {
  listEchos(): Promise<EchoDevice[]>;
  listSmartDevices(): Promise<SmartDevice[]>;
  listRoutines(): Promise<Routine[]>;
  runRoutine(routineId: string, echoDeviceId: string): Promise<void>;
  deviceAction(entityId: string, action: DeviceAction, brightness?: number): Promise<void>;
  /** Remove o dispositivo da conta Alexa (irreversível). */
  deleteSmartDevice(entityId: string): Promise<void>;
  speak(echoDeviceId: string, text: string): Promise<void>;
  setVolume(echoDeviceId: string, volume: number): Promise<void>;
  playSpotify(echoDeviceId: string, query: string): Promise<void>;
  /** Para (pausa) o que estiver tocando no Echo. */
  stopMusic(echoDeviceId: string): Promise<void>;
  /** Devolve um identificador opaco para apagar o alarme depois. */
  createAlarm(echoDeviceId: string, at: Date, label: string): Promise<string>;
  deleteAlarm(handle: string): Promise<void>;
}
