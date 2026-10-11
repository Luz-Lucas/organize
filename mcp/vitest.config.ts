import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    env: { TZ: 'UTC' },
    testTimeout: 20_000,
  },
});
