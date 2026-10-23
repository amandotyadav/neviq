import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globalSetup: ['tests/globalSetup.js'],
    testTimeout: 30000,
    hookTimeout: 180000,
    pool: 'forks',
  },
});
