import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { collegeQuerySchema } from '../validators/schemas.js';
import { Announcement, serializeAnnouncement } from '../models/Announcement.js';
import { College, serializeCollege } from '../models/College.js';
import { Resource, serializeResource } from '../models/Resource.js';
import { getDeadlines, getNextMoves } from '../services/nextMoves.js';
import { escapeRegex, send } from '../utils/http.js';

export const campusRouter = Router();
campusRouter.use(requireAuth);

/** Published, unexpired announcements for the student's own college only. */
campusRouter.get('/announcements', async (req, res) => {
  const collegeId = req.user.profile?.collegeId;
  if (!collegeId) return send(res, [], { meta: { reason: 'no_college' } });
  const now = new Date();
  const [items, college] = await Promise.all([
    Announcement.find({
      collegeId,
      status: 'published',
      $or: [{ expiresAt: null }, { expiresAt: { $gt: now } }],
    }).sort({ publishedAt: -1 }).limit(50).lean(),
    College.findById(collegeId).lean(),
  ]);
  send(res, items.map((a) => serializeAnnouncement(a, college?.name)));
});

/** Public college directory for onboarding search. */
export const collegesRouter = Router();
collegesRouter.get('/', validate({ query: collegeQuerySchema }), async (req, res) => {
  const filter = { listed: true };
  if (req.valid.query.q) {
    const rx = new RegExp(escapeRegex(req.valid.query.q), 'i');
    filter.$or = [{ name: rx }, { shortName: rx }, { aliases: rx }, { city: rx }];
  }
  const colleges = await College.find(filter).sort({ name: 1 }).limit(30).lean();
  send(res, colleges.map(serializeCollege));
});

export const meRouter = Router();
meRouter.use(requireAuth);
meRouter.get('/deadlines', async (req, res) => send(res, await getDeadlines(req.user)));
meRouter.get('/next-moves', async (req, res) => send(res, await getNextMoves(req.user)));

export const resourcesRouter = Router();
resourcesRouter.use(requireAuth);
resourcesRouter.get('/', async (_req, res) => {
  const resources = await Resource.find().sort({ title: 1 }).lean();
  send(res, resources.map(serializeResource));
});
