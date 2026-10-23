import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { opportunityQuerySchema, idParams, eligibilityCheckSchema } from '../validators/schemas.js';
import { searchOpportunities, getVisibleOpportunity, recommendedMatches, userStateFor, presentWithMatch, visibilityFilter } from '../services/opportunities.js';
import { checkEligibility } from '../eligibility/engine.js';
import { SavedOpportunity } from '../models/SavedOpportunity.js';
import { Opportunity, serializeOpportunity } from '../models/Opportunity.js';
import { send } from '../utils/http.js';

export const opportunitiesRouter = Router();
opportunitiesRouter.use(requireAuth);

opportunitiesRouter.get('/', validate({ query: opportunityQuerySchema }), async (req, res) => {
  const { items, meta } = await searchOpportunities(req.user, req.valid.query);
  send(res, items, { meta });
});

opportunitiesRouter.get('/:id', validate({ params: idParams }), async (req, res) => {
  const opp = await getVisibleOpportunity(req.user, req.valid.params.id);
  const state = await userStateFor(req.user, [opp._id]);
  send(res, presentWithMatch(opp, req.user, state).item);
});

opportunitiesRouter.post('/:id/save', validate({ params: idParams }), async (req, res) => {
  const opp = await getVisibleOpportunity(req.user, req.valid.params.id);
  await SavedOpportunity.updateOne(
    { userId: req.user._id, opportunityId: opp._id },
    { $setOnInsert: { userId: req.user._id, opportunityId: opp._id } },
    { upsert: true },
  );
  send(res, { opportunityId: String(opp._id), isSaved: true });
});

opportunitiesRouter.delete('/:id/save', validate({ params: idParams }), async (req, res) => {
  await SavedOpportunity.deleteOne({ userId: req.user._id, opportunityId: req.valid.params.id });
  send(res, { opportunityId: req.valid.params.id, isSaved: false });
});

export const savedRouter = Router();
savedRouter.use(requireAuth);
savedRouter.get('/', async (req, res) => {
  const saved = await SavedOpportunity.find({ userId: req.user._id }).sort({ createdAt: -1 }).lean();
  const opps = await Opportunity.find({ _id: { $in: saved.map((s) => s.opportunityId) }, ...visibilityFilter(req.user) }).lean();
  const byId = new Map(opps.map((o) => [String(o._id), o]));
  const state = await userStateFor(req.user, opps.map((o) => o._id));
  send(res, saved.map((s) => byId.get(String(s.opportunityId))).filter(Boolean).map((o) => presentWithMatch(o, req.user, state).item));
});

export const matchesRouter = Router();
matchesRouter.use(requireAuth);
matchesRouter.get('/', async (req, res) => {
  const { items, excludedIneligible, excludedRestricted, excludedUnconfirmed } = await recommendedMatches(req.user, { limit: 10 });
  send(res, items, {
    meta: {
      excludedIneligible,
      excludedRestricted,
      excludedUnconfirmed,
      criteria: 'Verified, open or upcoming listings, excluding ones where a mandatory criterion is unmet or that are restricted to a group or field Naviq cannot confirm you belong to, or where nothing could be checked against your profile. Those still appear in Discover.',
    },
  });
});

export const eligibilityRouter = Router();
eligibilityRouter.use(requireAuth);
eligibilityRouter.post('/check', validate({ body: eligibilityCheckSchema }), async (req, res) => {
  const opp = await getVisibleOpportunity(req.user, req.valid.body.opportunityId);
  const result = checkEligibility(opp, req.user.profile, { declarations: req.valid.body.declarations });
  send(res, { ...result, opportunity: serializeOpportunity(opp) });
});
