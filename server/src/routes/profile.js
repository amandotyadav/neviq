import { Router } from 'express';
import { User, serializeUser } from '../models/User.js';
import { College, normalizeCollegeName } from '../models/College.js';
import { SavedOpportunity } from '../models/SavedOpportunity.js';
import { Application } from '../models/Application.js';
import { Roadmap } from '../models/Roadmap.js';
import { Draft } from '../models/Draft.js';
import { verifyPassword } from '../auth/tokens.js';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { profilePatchSchema, deleteAccountSchema } from '../validators/schemas.js';
import { send } from '../utils/http.js';
import { badRequest, unauthorized } from '../utils/errors.js';

const router = Router();
router.use(requireAuth);

router.get('/', (req, res) => send(res, { user: serializeUser(req.user) }));

router.patch('/', validate({ body: profilePatchSchema }), async (req, res) => {
  const { name, profile, notificationPrefs, completeOnboarding } = req.valid.body;
  const user = req.user;
  if (name) user.name = name;

  if (profile) {
    const { collegeId, customCollegeName, ...rest } = profile;
    if (collegeId !== undefined) {
      if (collegeId === null) {
        user.profile.collegeId = null;
        user.profile.collegeName = undefined;
      } else {
        const college = await College.findById(collegeId);
        if (!college) throw badRequest('Selected college was not found');
        user.profile.collegeId = college._id;
        user.profile.collegeName = college.name;
      }
    } else if (customCollegeName) {
      // Institution not yet listed: find-or-create an unlisted record.
      const normalizedName = normalizeCollegeName(customCollegeName);
      const college = await College.findOneAndUpdate(
        { normalizedName },
        { $setOnInsert: { name: customCollegeName.trim(), normalizedName, listed: false } },
        { upsert: true, returnDocument: 'after' },
      );
      user.profile.collegeId = college._id;
      user.profile.collegeName = college.name;
    }
    for (const [key, value] of Object.entries(rest)) {
      if (key === 'links') user.profile.links = { ...(user.profile.links?.toObject?.() ?? user.profile.links ?? {}), ...value };
      else user.profile[key] = value === null ? undefined : value;
    }
  }
  if (notificationPrefs) user.notificationPrefs = { ...user.notificationPrefs.toObject(), ...notificationPrefs };
  if (completeOnboarding && !user.onboardingCompletedAt) user.onboardingCompletedAt = new Date();

  await user.save();
  send(res, { user: serializeUser(user) });
});

/** Permanently deletes the account and all student-owned data. */
router.delete('/', validate({ body: deleteAccountSchema }), async (req, res) => {
  const user = await User.findById(req.user._id).select('+passwordHash');
  if (!(await verifyPassword(req.valid.body.password, user.passwordHash))) throw unauthorized('Password is incorrect.');
  const userId = user._id;
  await Promise.all([
    SavedOpportunity.deleteMany({ userId }),
    Application.deleteMany({ userId }),
    Roadmap.deleteMany({ userId }),
    Draft.deleteMany({ userId }),
  ]);
  await User.deleteOne({ _id: userId });
  send(res, { deleted: true });
});

export default router;
