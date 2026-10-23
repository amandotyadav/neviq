import 'dotenv/config';
import { z } from 'zod';

/**
 * Environment validation. The server refuses to start with an invalid
 * configuration instead of failing later in confusing ways.
 * GEMINI_API_KEY is optional: without it, AI routes respond 503 while all
 * other features keep working.
 */
const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(4000),
  MONGODB_URI: z.string().min(1, 'MONGODB_URI is required').optional(),
  JWT_SECRET: z.string().min(32, 'JWT_SECRET must be at least 32 characters').optional(),
  JWT_EXPIRES_IN: z.string().default('7d'),
  CORS_ORIGINS: z.string().default(''),
  GEMINI_API_KEY: z.string().optional(),
  GEMINI_MODEL: z.string().default('gemini-3.5-flash-lite'),
  AI_TIMEOUT_MS: z.coerce.number().int().positive().default(30000),
  AI_REQUESTS_PER_HOUR: z.coerce.number().int().positive().default(40),
  ENABLE_DAILY_REFRESH: z.enum(['true', 'false']).optional(),
  REFRESH_HOUR_IST: z.coerce.number().int().min(0).max(23).default(3),
  REFRESH_ON_START: z.enum(['true', 'false']).default('false'),
  LOG_LEVEL: z.enum(['debug', 'info', 'warn', 'error']).default('info'),
  TRUST_PROXY: z.coerce.number().int().min(0).default(0),
});

function load() {
  const parsed = schema.safeParse(process.env);
  if (!parsed.success) {
    const issues = parsed.error.issues.map((i) => `  - ${i.path.join('.')}: ${i.message}`).join('\n');
    throw new Error(`Invalid environment configuration:\n${issues}`);
  }
  const env = parsed.data;
  if (env.NODE_ENV !== 'test') {
    if (!env.MONGODB_URI) throw new Error('Invalid environment configuration:\n  - MONGODB_URI is required');
    if (!env.JWT_SECRET) throw new Error('Invalid environment configuration:\n  - JWT_SECRET is required (32+ chars)');
  }
  if (!env.JWT_SECRET && env.NODE_ENV === 'test') {
    env.JWT_SECRET = 'test-secret-test-secret-test-secret-1234';
  }
  if (env.GEMINI_API_KEY === '') env.GEMINI_API_KEY = undefined;
  return Object.freeze(env);
}

export const env = load();
