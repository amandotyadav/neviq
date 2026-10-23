import mongoose from 'mongoose';
import { notFound } from './errors.js';

/** Consistent success envelope: { data, meta? } */
export function send(res, data, { status = 200, meta } = {}) {
  res.status(status).json(meta ? { data, meta } : { data });
}

export function assertObjectId(id, label = 'Resource') {
  if (!mongoose.isValidObjectId(id)) throw notFound(`${label} not found`);
  return id;
}

export function escapeRegex(input) {
  return input.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

export function paginate(items, page, limit) {
  const total = items.length;
  const start = (page - 1) * limit;
  return {
    items: items.slice(start, start + limit),
    meta: { page, limit, total, totalPages: Math.max(1, Math.ceil(total / limit)) },
  };
}

export const normalize = (s) => String(s ?? '').trim().toLowerCase();
