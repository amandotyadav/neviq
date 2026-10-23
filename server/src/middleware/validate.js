import { badRequest } from '../utils/errors.js';

/**
 * Validates request parts with Zod. Parsed (and stripped) values are placed
 * on `req.valid` so unknown fields — such as `role` — never reach handlers.
 */
export function validate({ body, query, params } = {}) {
  return (req, _res, next) => {
    req.valid = req.valid ?? {};
    for (const [part, schema] of [['body', body], ['query', query], ['params', params]]) {
      if (!schema) continue;
      const parsed = schema.safeParse(req[part] ?? {});
      if (!parsed.success) {
        throw badRequest('Some fields are invalid', parsed.error.issues.map((i) => ({
          field: i.path.join('.'),
          message: i.message,
        })));
      }
      req.valid[part] = parsed.data;
    }
    next();
  };
}
