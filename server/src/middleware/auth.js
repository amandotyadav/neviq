import mongoose from 'mongoose';
import { User } from '../models/User.js';
import { verifyToken } from '../auth/tokens.js';
import { forbidden, unauthorized } from '../utils/errors.js';

/**
 * Authenticates the bearer token and loads the user. Identity always comes
 * from the token — never from a user id in the request body or query.
 */
export async function requireAuth(req, _res, next) {
  const header = req.get('authorization') ?? '';
  const [scheme, token] = header.split(' ');
  if (scheme !== 'Bearer' || !token) throw unauthorized();

  let payload;
  try {
    payload = verifyToken(token);
  } catch {
    throw unauthorized('Your session has expired. Please sign in again.');
  }
  if (!mongoose.isValidObjectId(payload.sub)) throw unauthorized();
  const user = await User.findById(payload.sub);
  if (!user || (user.tokenVersion ?? 0) !== payload.ver) {
    throw unauthorized('Your session has ended. Please sign in again.');
  }
  req.user = user;
  next();
}

export function requireRole(...roles) {
  return (req, _res, next) => {
    if (!req.user || !roles.includes(req.user.role)) throw forbidden();
    next();
  };
}

/** Whether the admin may manage resources for the given college. */
export function canManageCollege(user, collegeId) {
  if (user.role === 'platform_admin') return true;
  if (user.role !== 'college_admin' || !collegeId) return false;
  return (user.adminCollegeIds ?? []).some((id) => String(id) === String(collegeId));
}
