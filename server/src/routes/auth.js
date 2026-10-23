import { Router } from 'express';
import { User, serializeUser } from '../models/User.js';
import { hashPassword, verifyPassword, issueToken } from '../auth/tokens.js';
import { validate } from '../middleware/validate.js';
import { requireAuth } from '../middleware/auth.js';
import { authLimiter } from '../middleware/rateLimits.js';
import { registerSchema, loginSchema } from '../validators/schemas.js';
import { send } from '../utils/http.js';
import { conflict, unauthorized } from '../utils/errors.js';

const router = Router();

/**
 * Registration always creates a student. The schema is strict, so a request
 * that includes `role` or admin fields is rejected outright.
 */
router.post('/register', authLimiter, validate({ body: registerSchema }), async (req, res) => {
  const { name, email, password } = req.valid.body;
  if (await User.exists({ email })) throw conflict('An account with this email already exists. Try signing in.');
  const user = await User.create({ name, email, passwordHash: await hashPassword(password), role: 'student' });
  send(res, { token: issueToken(user), user: serializeUser(user) }, { status: 201 });
});

router.post('/login', authLimiter, validate({ body: loginSchema }), async (req, res) => {
  const { email, password } = req.valid.body;
  const user = await User.findOne({ email }).select('+passwordHash');
  // Same message for unknown email and wrong password.
  if (!user || !(await verifyPassword(password, user.passwordHash))) throw unauthorized('Email or password is incorrect.');
  send(res, { token: issueToken(user), user: serializeUser(user) });
});

/** Revokes every token issued to this user (all devices). */
router.post('/logout', requireAuth, async (req, res) => {
  await User.updateOne({ _id: req.user._id }, { $inc: { tokenVersion: 1 } });
  send(res, { signedOut: true });
});

router.get('/me', requireAuth, (req, res) => send(res, { user: serializeUser(req.user) }));

export default router;
