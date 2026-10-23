import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { draftPatchSchema, draftCreateSchema, idParams } from '../validators/schemas.js';
import { Draft, serializeDraft } from '../models/Draft.js';
import { getVisibleOpportunity } from '../services/opportunities.js';
import { send } from '../utils/http.js';
import { notFound } from '../utils/errors.js';

const router = Router();
router.use(requireAuth);

async function ownDraft(req) {
  const draft = await Draft.findOne({ _id: req.valid.params.id, userId: req.user._id });
  if (!draft) throw notFound('Draft not found');
  return draft;
}

router.get('/', async (req, res) => {
  const filter = { userId: req.user._id };
  if (typeof req.query.opportunityId === 'string' && /^[a-f\d]{24}$/i.test(req.query.opportunityId)) filter.opportunityId = req.query.opportunityId;
  const drafts = await Draft.find(filter).sort({ updatedAt: -1 }).limit(100).lean();
  send(res, drafts.map(serializeDraft));
});

router.post('/', validate({ body: draftCreateSchema }), async (req, res) => {
  const b = req.valid.body;
  if (b.opportunityId) await getVisibleOpportunity(req.user, b.opportunityId);
  const draft = await Draft.create({ ...b, userId: req.user._id, generatedBy: 'student', reviewedAt: new Date() });
  send(res, serializeDraft(draft), { status: 201 });
});

router.get('/:id', validate({ params: idParams }), async (req, res) => send(res, serializeDraft(await ownDraft(req))));

router.patch('/:id', validate({ params: idParams, body: draftPatchSchema }), async (req, res) => {
  const draft = await ownDraft(req);
  const b = req.valid.body;
  for (const key of ['title', 'subject', 'body']) if (b[key] !== undefined) draft[key] = b[key];
  if (b.markReviewed) draft.reviewedAt = new Date();
  await draft.save();
  send(res, serializeDraft(draft));
});

router.delete('/:id', validate({ params: idParams }), async (req, res) => {
  const draft = await ownDraft(req);
  await draft.deleteOne();
  send(res, { deleted: true, id: String(draft._id) });
});

export default router;
