import type { AlexaGateway, DeviceAction } from '../src/gateway.js';

export class FakeGateway implements AlexaGateway {
  calls: string[] = [];
  failOn = new Set<string>();
  deleted: string[] = [];
  stopped: string[] = [];
  alarms = new Map<string, { echo: string; at: Date; label: string }>();
  private next = 1;

  private async record(name: string, detail: string): Promise<void> {
    this.calls.push(`${name}(${detail})`);
    if (this.failOn.has(name)) throw new Error(`${name} falhou`);
  }

  async listEchos() { return [{ id: 'ECHO', name: 'Echo do quarto', online: true }]; }
  async listSmartDevices() { return [{ id: 'luz1', name: 'Luz do quarto', operations: ['turnOn', 'turnOff', 'setBrightness'] }]; }
  async listRoutines() { return [{ id: 'r1', name: 'Boa noite' }]; }
  async runRoutine(routineId: string, echo: string) { await this.record('runRoutine', `${routineId},${echo}`); }
  async deviceAction(entityId: string, action: DeviceAction, brightness?: number) {
    await this.record('deviceAction', `${entityId},${action}${brightness === undefined ? '' : `,${brightness}`}`);
  }
  async deleteSmartDevice(entityId: string) {
    await this.record('deleteSmartDevice', entityId);
    this.deleted.push(entityId);
  }
  async speak(echo: string, text: string) { await this.record('speak', `${echo},${text}`); }
  async setVolume(echo: string, volume: number) { await this.record('setVolume', `${echo},${volume}`); }
  async playSpotify(echo: string, query: string) { await this.record('playSpotify', `${echo},${query}`); }
  async stopMusic(echo: string) {
    await this.record('stopMusic', echo);
    this.stopped.push(echo);
  }
  async createAlarm(echo: string, at: Date, label: string) {
    await this.record('createAlarm', `${echo},${at.toISOString()},${label}`);
    const handle = `alarme-${this.next++}`;
    this.alarms.set(handle, { echo, at, label });
    return handle;
  }
  async deleteAlarm(handle: string) {
    await this.record('deleteAlarm', handle);
    this.alarms.delete(handle);
  }
}
