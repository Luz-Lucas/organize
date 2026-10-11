import { describe, expect, it } from 'vitest';
import { findApplianceId, mapRoutines, mapSmartEntities } from '../src/alexa-remote-gateway.js';
import { toDeviceActions, toPlan, toPresenceSource } from '../src/supabase-store.js';

describe('toPlan', () => {
  const row = {
    id: 'p1', label: 'Aula', days: [1], time: '07:00:00', echo_device_id: 'ECHO', spotify_query: 'lofi',
    music_first: true, briefing_delay_min: 3, volume: 30, fallback_alarm: true, enabled: true,
    music_stop_after_sec: 30, after_music: 'headlines',
  };

  it('mapeia music_stop_after_sec e after_music', () => {
    expect(toPlan(row)).toMatchObject({ musicStopAfterSec: 30, afterMusic: 'headlines' });
    expect(toPlan({ ...row, after_music: 'end' }).afterMusic).toBe('end');
  });

  it('ausente ou desconhecido vira "não parar" e briefing', () => {
    expect(toPlan({ ...row, music_stop_after_sec: null }).musicStopAfterSec).toBeNull();
    expect(toPlan({ ...row, music_stop_after_sec: undefined }).musicStopAfterSec).toBeNull();
    expect(toPlan({ ...row, after_music: 'x' }).afterMusic).toBe('briefing');
    expect(toPlan({ ...row, after_music: undefined }).afterMusic).toBe('briefing');
  });
});

describe('toPlan: despertar inteligente', () => {
  const row = {
    id: 'p1', label: 'Aula', days: [1], time: '07:00:00', echo_device_id: 'ECHO', spotify_query: 'lofi',
    music_first: true, briefing_delay_min: 3, volume: 30, fallback_alarm: true, enabled: true,
  };

  it('linha antiga (sem as colunas novas) ganha padrões seguros', () => {
    expect(toPlan(row)).toMatchObject({
      includeWeather: true, deviceActions: [], phoneAlarm: 'fallback', briefingDelaySec: null,
    });
  });

  it('mapeia os campos novos', () => {
    const actions = [{ entityId: 'luz1', name: 'Luz', action: 'setBrightness', brightness: 40, delayMin: 5 }];
    expect(toPlan({
      ...row, include_weather: false, device_actions: actions, phone_alarm: 'always', briefing_delay_sec: 10,
    })).toMatchObject({ includeWeather: false, deviceActions: actions, phoneAlarm: 'always', briefingDelaySec: 10 });
    expect(toPlan({ ...row, briefing_delay_sec: 0 }).briefingDelaySec).toBe(0);
  });

  it('phone_alarm desconhecido vira fallback', () => {
    expect(toPlan({ ...row, phone_alarm: 'x' }).phoneAlarm).toBe('fallback');
  });
});

describe('toDeviceActions', () => {
  it('descarta entradas inválidas e normaliza faixas', () => {
    expect(toDeviceActions([
      { entityId: 'a', name: 'A', action: 'turnOn' },
      { entityId: 'b', name: 'B', action: 'turnOff', delayMin: 99 },
      { entityId: 'c', name: 'C', action: 'setBrightness', brightness: 150, delayMin: 2 },
      { entityId: 'd', name: 'D', action: 'setBrightness' },
      { entityId: 'e', name: 'E', action: 'explode' },
      { name: 'sem id', action: 'turnOn' },
      null, 'x',
    ])).toEqual([
      { entityId: 'a', name: 'A', action: 'turnOn', delayMin: 0 },
      { entityId: 'b', name: 'B', action: 'turnOff', delayMin: 30 },
      { entityId: 'c', name: 'C', action: 'setBrightness', brightness: 100, delayMin: 2 },
    ]);
  });

  it('não-array vira lista vazia', () => {
    expect(toDeviceActions(null)).toEqual([]);
    expect(toDeviceActions({})).toEqual([]);
    expect(toDeviceActions(undefined)).toEqual([]);
  });
});

describe('toPresenceSource', () => {
  it('sem linhas: sem casa, exige casa, sem localização', () => {
    expect(toPresenceSource(null, null)).toEqual({ home: null, requireHome: true, location: null });
  });

  it('com casa e localização', () => {
    const r = toPresenceSource(
      { home_lat: -19.9167, home_lon: -45.7, home_radius_m: 80, require_home: false },
      { lat: -22.2, lon: -45.6, accuracy_m: 12, reported_at: '2026-10-13T10:00:00Z' },
    );
    expect(r).toEqual({
      home: { lat: -19.9167, lon: -45.7, radiusM: 80 }, requireHome: false,
      location: { lat: -22.2, lon: -45.6, accuracyM: 12, reportedAt: new Date('2026-10-13T10:00:00Z') },
    });
  });

  it('casa pela metade vira sem casa; raio ausente vira 50; precisão ausente vira null', () => {
    expect(toPresenceSource({ home_lat: 1, home_lon: null }, null).home).toBeNull();
    expect(toPresenceSource({ home_lat: 1, home_lon: 2 }, null).home).toEqual({ lat: 1, lon: 2, radiusM: 50 });
    expect(toPresenceSource(null, { lat: 1, lon: 2, accuracy_m: null, reported_at: '2026-10-13T10:00:00Z' }).location?.accuracyM).toBeNull();
  });

  it('data de localização inválida é descartada', () => {
    expect(toPresenceSource(null, { lat: 1, lon: 2, reported_at: 'lixo' }).location).toBeNull();
  });
});

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
