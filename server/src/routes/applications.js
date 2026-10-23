import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { applicationCreateSchema, applicationPatchSchema, applicationQuerySchema, idParams } from '../validators/schemas.js';
import { Application, serializeApplication } from '../models/Application.js';
import { getVisibleOpportunity } from '../services/opportunities.js';
import { send } from '../utils/http.js';
import { conflict, notFound } from '../utils/errors.js';

const router = Router();
router.use(requireAuth);

/** Scoped lookup: a student can only ever load their own applications. */
async function ownApplication(req) {
  const app = await Application.findOne({ _id: req.valid.params.id, userId: req.user._id });
  if (!app) throw notFound('Application not found');
  return app;
}

router.get('/', validate({ query: applicationQuerySchema }), async (req, res) => {
  const filter = { userId: req.user._id, archived: req.valid.query.archived };
  if (req.valid.query.status) filter.status = req.valid.query.status;
  const apps = await Application.find(filter).sort({ updatedAt: -1 }).lean();
  send(res, apps.map(serializeApplication));
});

router.post('/', validate({ body: applicationCreateSchema }), async (req, res) => {
  const b = req.valid.body;
  const doc = { userId: req.user._id, status: b.status, notes: b.notes, nextAction: b.nextAction, nextActionDue: b.nextActionDue ?? null, appliedAt: b.appliedAt ?? null };
  if (b.opportunityId) {
    const opp = await getVisibleOpportunity(req.user, b.opportunityId);
    if (await Application.exists({ userId: req.user._id, opportunityId: opp._id })) {
      throw conflict('This opportunity is already in your tracker.');
    }
    Object.assign(doc, {
      opportunityId: opp._id,
      title: opp.title,
      organization: opp.organization,
      applicationUrl: opp.applicationUrl ?? opp.sourceUrl,
      deadline: b.deadline ?? opp.deadline ?? null,
    });
  } else {
    Object.assign(doc, { title: b.title, organization: b.organization, applicationUrl: b.applicationUrl || undefined, deadline: b.deadline ?? null });
  }
  if (doc.status === 'applied' && !doc.appliedAt) doc.appliedAt = new Date();
  doc.statusHistory = [{ status: doc.status, at: new Date() }];
  const app = await Application.create(doc);
  send(res, serializeApplication(app), { status: 201 });
});

router.get('/:id', validate({ params: idParams }), async (req, res) => {
  send(res, serializeApplication(await ownApplication(req)));
});

router.patch('/:id', validate({ params: idParams, body: applicationPatchSchema }), async (req, res) => {
  const app = await ownApplication(req);
  const b = req.valid.body;
  if (b.status && b.status !== app.status) {
    app.statusHistory.push({ status: b.status, at: new Date() });
    app.status = b.status;
    if (b.status === 'applied' && !app.appliedAt && b.appliedAt === undefined) app.appliedAt = new Date();
  }
  for (const key of ['title', 'organization', 'notes', 'deadline', 'nextActionDue', 'appliedAt', 'archived']) {
    if (b[key] !== undefined) app[key] = b[key];
  }
  if (b.nextAction !== undefined) app.nextAction = b.nextAction ?? undefined;
  if (b.nextAction === null) app.nextActionDue = null;
  if (b.applicationUrl !== undefined) app.applicationUrl = b.applicationUrl || undefined;
  await app.save();
  send(res, serializeApplication(app));
});

router.delete('/:id', validate({ params: idParams }), async (req, res) => {
  const app = await ownApplication(req);
  await app.deleteOne();
  send(res, { deleted: true, id: String(app._id) });
});

export default router;
