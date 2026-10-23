import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { milestonePatchSchema, milestoneCreateSchema, milestoneParams } from '../validators/schemas.js';
import { Roadmap, serializeRoadmap } from '../models/Roadmap.js';
import { Resource, serializeResource } from '../models/Resource.js';
import { send } from '../utils/http.js';
import { notFound } from '../utils/errors.js';

const router = Router();
router.use(requireAuth);

export async function presentRoadmap(roadmap) {
  if (!roadmap) return null;
  const ids = roadmap.milestones.flatMap((m) => m.verifiedResourceIds ?? []);
  const resources = await Resource.find({ _id: { $in: ids } }).lean();
  return serializeRoadmap(roadmap, new Map(resources.map((r) => [String(r._id), serializeResource(r)])));
}

async function activeRoadmap(userId) {
  return Roadmap.findOne({ userId, status: 'active' });
}

router.get('/', async (req, res) => {
  send(res, await presentRoadmap(await activeRoadmap(req.user._id)));
});

/** Manual milestone creation works without AI. Creates a roadmap if needed. */
router.post('/milestones', validate({ body: milestoneCreateSchema }), async (req, res) => {
  const b = req.valid.body;
  let roadmap = await activeRoadmap(req.user._id);
  if (!roadmap) {
    roadmap = new Roadmap({ userId: req.user._id, goal: b.goal ?? req.user.profile?.careerGoal ?? 'My goals', generatedBy: 'student', milestones: [] });
  }
  roadmap.milestones.push({
    title: b.title, purpose: b.purpose, steps: b.steps, skills: b.skills, priority: b.priority,
    targetDate: b.targetDate ?? null, order: roadmap.milestones.length, source: 'student',
  });
  await roadmap.save();
  send(res, await presentRoadmap(roadmap), { status: 201 });
});

router.patch('/milestones/:milestoneId', validate({ params: milestoneParams, body: milestonePatchSchema }), async (req, res) => {
  const roadmap = await activeRoadmap(req.user._id);
  const milestone = roadmap?.milestones.id(req.valid.params.milestoneId);
  if (!milestone) throw notFound('Milestone not found');
  const b = req.valid.body;
  if (b.status) {
    milestone.status = b.status;
    // Completion is only ever recorded when the student marks it.
    milestone.completedAt = b.status === 'completed' ? new Date() : null;
  }
  for (const key of ['priority', 'order', 'targetDate', 'title']) if (b[key] !== undefined) milestone[key] = b[key];
  await roadmap.save();
  send(res, await presentRoadmap(roadmap));
});

router.delete('/milestones/:milestoneId', validate({ params: milestoneParams }), async (req, res) => {
  const roadmap = await activeRoadmap(req.user._id);
  const milestone = roadmap?.milestones.id(req.valid.params.milestoneId);
  if (!milestone) throw notFound('Milestone not found');
  milestone.deleteOne();
  await roadmap.save();
  send(res, await presentRoadmap(roadmap));
});

export default router;
