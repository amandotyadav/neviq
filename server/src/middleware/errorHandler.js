import { AppError } from '../utils/errors.js';
import { logger } from '../utils/logger.js';
import { env } from '../config/env.js';

export function notFoundHandler(req, res) {
  res.status(404).json({ error: { code: 'NOT_FOUND', message: `No route for ${req.method} ${req.path}` } });
}

// eslint-disable-next-line no-unused-vars
export function errorHandler(err, req, res, _next) {
  if (err instanceof AppError) {
    if (err.status >= 500) logger.warn('Handled server error', { code: err.code, path: req.path });
    return res.status(err.status).json({ error: { code: err.code, message: err.message, details: err.details } });
  }
  if (err?.type === 'entity.parse.failed') {
    return res.status(400).json({ error: { code: 'BAD_REQUEST', message: 'Request body is not valid JSON' } });
  }
  if (err?.type === 'entity.too.large') {
    return res.status(413).json({ error: { code: 'PAYLOAD_TOO_LARGE', message: 'Request body is too large' } });
  }
  if (err?.name === 'ValidationError') {
    return res.status(400).json({
      error: {
        code: 'BAD_REQUEST',
        message: 'Some fields are invalid',
        details: Object.values(err.errors ?? {}).map((e) => ({ field: e.path, message: e.message })),
      },
    });
  }
  if (err?.code === 11000) {
    return res.status(409).json({ error: { code: 'CONFLICT', message: 'This record already exists' } });
  }
  logger.error('Unhandled error', { path: req.path, method: req.method, error: err });
  return res.status(500).json({
    error: {
      code: 'INTERNAL',
      message: env.NODE_ENV === 'production' ? 'Something went wrong on our side.' : String(err?.message ?? err),
    },
  });
}
