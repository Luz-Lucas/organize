import { describe, expect, it } from 'vitest';
import { findApplianceId, mapRoutines, mapSmartEntities } from '../src/alexa-remote-gateway.js';

describe('mapSmartEntities', () => {
  it('mantém só dispositivos controláveis e as operações conhecidas', () => {
    const raw = [
      { id: 'e1', displayName: 'Luz do quarto', supportedOperations: ['turnOn', 'turnOff', 'setBrightness', 'setColor'] },
      { id: 'e2', displayName: 'Sensor da porta', supportedOperations: [] },
      { id: 'e3', displayName: 'Tomada', supportedOperations: ['turnOff', 'turnOn'] },
      { displayName: 'sem id' },
    ];
    expect(mapSmartEntities(raw)).toEqual([
      { id: 'e1', name: 'Luz do quarto', operations: ['turnOn', 'turnOff', 'setBrightness'] },
      { id: 'e3', name: 'Tomada', operations: ['turnOn', 'turnOff'] },
    ]);
  });

  it('resposta inesperada vira lista vazia', () => {
    expect(mapSmartEntities({ erro: true })).toEqual([]);
  });
});

describe('mapRoutines', () => {
  it('usa o nome ou a frase de ativação', () => {
    const raw = [
      { automationId: 'a1', name: 'Boa noite' },
      { automationId: 'a2', name: null, triggers: [{ payload: { utterance: 'hora de estudar' } }] },
      { automationId: 'a3' },
      { name: 'sem id' },
    ];
    expect(mapRoutines(raw)).toEqual([
      { id: 'a1', name: 'Boa noite' },
      { id: 'a2', name: 'hora de estudar' },
      { id: 'a3', name: 'Rotina sem nome' },
    ]);
  });
});

describe('findApplianceId', () => {
  it('acha o applianceId pelo entityId em getSmarthomeDevices', () => {
    const raw = { locationDetails: { Default_Location: { amazonBridgeDetails: { amazonBridgeDetails: {
      'LambdaBridge_x': { applianceDetails: { applianceDetails: {
        'SKILL_abc': { applianceId: 'SKILL_abc', entityId: 'ent-1', friendlyName: 'Luz' } } } } } } } } };
    expect(findApplianceId(raw, 'ent-1')).toBe('SKILL_abc');
    expect(findApplianceId(raw, 'nao-existe')).toBeNull();
  });
});
