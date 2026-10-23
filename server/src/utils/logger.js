/**
 * Small structured JSON logger with field redaction. Avoids logging request
 * bodies, tokens, passwords, and other personal data.
 */
const LEVELS = { debug: 10, info: 20, warn: 30, error: 40 };
const REDACT = /pass(word)?|token|secret|authorization|apikey|api_key|income/i;

let threshold = LEVELS[process.env.LOG_LEVEL] ?? LEVELS.info;
const silent = process.env.NODE_ENV === 'test';

function redact(value, depth = 0) {
  if (value === null || typeof value !== 'object' || depth > 4) return value;
  if (value instanceof Error) return { name: value.name, message: value.message };
  const out = Array.isArray(value) ? [] : {};
  for (const [k, v] of Object.entries(value)) {
    out[k] = REDACT.test(k) ? '[redacted]' : redact(v, depth + 1);
  }
  return out;
}

function write(level, message, meta) {
  if (silent || LEVELS[level] < threshold) return;
  const line = JSON.stringify({ time: new Date().toISOString(), level, message, ...(meta ? redact(meta) : {}) });
  (level === 'error' || level === 'warn' ? process.stderr : process.stdout).write(`${line}\n`);
}

export const logger = {
  setLevel(level) { threshold = LEVELS[level] ?? threshold; },
  debug: (m, meta) => write('debug', m, meta),
  info: (m, meta) => write('info', m, meta),
  warn: (m, meta) => write('warn', m, meta),
  error: (m, meta) => write('error', m, meta),
};
