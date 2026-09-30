import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    env: { TZ: 'UTC' }, // simula a VPS: a lógica não pode depender do fuso da máquina
  },
});
