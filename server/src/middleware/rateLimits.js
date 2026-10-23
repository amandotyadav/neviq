import rateLimit from 'express-rate-limit';
import { env } from '../config/env.js';

const json = (message) => (_req, res) =>
  res.status(429).json({ error: { code: 'RATE_LIMITED', message } });

const disabled = env.NODE_ENV === 'test';

export const generalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 600,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  skip: () => disabled,
  handler: json('Too many requests. Please slow down.'),
});

export const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 20,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  skip: () => disabled,
  handler: json('Too many sign-in attempts. Try again in a few minutes.'),
});

/** AI calls are limited per authenticated user, not per IP. */
export const aiLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  limit: env.AI_REQUESTS_PER_HOUR,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  keyGenerator: (req) => String(req.user?._id ?? 'anon'),
  skip: () => disabled,
  handler: json('You have reached the hourly Saathi limit. Try again later.'),
});
