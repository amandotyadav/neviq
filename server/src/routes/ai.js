import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { aiLimiter } from '../middleware/rateLimits.js';
import { chatSchema, roadmapGenerateSchema, draftEmailSchema, resumeSchema, idParams } from '../validators/schemas.js';
import { runSaathi } from '../ai/saathi.js';
import { generateRoadmap, generateDraft, explainMatch } from '../ai/generators.js';
import { requireAI, getAIProvider } from '../ai/provider.js';
import { getVisibleOpportunity } from '../services/opportunities.js';
import { checkEligibility } from '../eligibility/engine.js';
import { scoreOpportunity } from '../matching/engine.js';
import { Roadmap } from '../models/Roadmap.js';
import { Resource } from '../models/Resource.js';
import { Draft, serializeDraft } from '../models/Draft.js';
import { presentRoadmap } from './roadmap.js';
import { send } from '../utils/http.js';

const router = Router();
router.use(requireAuth);

/** Lets the client show AI availability without making a model call. */
router.get('/status', (_req, res) => {
  const provider = getAIProvider();
  send(res, { available: Boolean(provider), model: provider?.model ?? null });
});

router.use(aiLimiter);

router.post('/chat', validate({ body: chatSchema }), async (req, res) => {
  send(res, await runSaathi(req.user, req.valid.body));
});

router.post('/roadmap', validate({ body: roadmapGenerateSchema }), async (req, res) => {
  requireAI();
  const { goal, opportunityId } = req.valid.body;
  const opportunity = opportunityId ? await getVisibleOpportunity(req.user, opportunityId) : null;
  const eligibility = opportunity ? checkEligibility(opportunity, req.user.profile) : null;
  const resources = await Resource.find().lean();
  const generated = await generateRoadmap(req.user, { goal, opportunity, eligibility, resources });

  // Only persist after the AI output validated successfully.
  await Roadmap.updateMany({ userId: req.user._id, status: 'active' }, { $set: { status: 'archived' } });
  const roadmap = await Roadmap.create({
    userId: req.user._id,
    goal,
    summary: generated.summary,
    generatedBy: 'ai',
    aiModel: generated.model,
    targetOpportunityId: opportunity?._id ?? null,
    milestones: generated.milestones,
  });
  send(res, await presentRoadmap(roadmap), { status: 201 });
});

async function saveDraft(req, kind, opportunity, generated) {
  const draft = await Draft.create({
    userId: req.user._id,
    opportunityId: opportunity?._id ?? null,
    kind,
    title: opportunity ? `${opportunity.title} — ${kind.replace('_', ' ')}` : kind.replace('_', ' '),
    subject: generated.subject,
    body: generated.body,
    generatedBy: 'ai',
    aiModel: generated.model,
    missingInformation: generated.missingInformation,
  });
  return serializeDraft(draft);
}

router.post('/draft-email', validate({ body: draftEmailSchema }), async (req, res) => {
  requireAI();
  const b = req.valid.body;
  const opportunity = await getVisibleOpportunity(req.user, b.opportunityId);
  const generated = await generateDraft(req.user, { kind: 'email', opportunity, tone: b.tone, recipientName: b.recipientName, extraContext: b.extraContext });
  send(res, await saveDraft(req, 'email', opportunity, generated), { status: 201 });
});

router.post('/resume', validate({ body: resumeSchema }), async (req, res) => {
  requireAI();
  const b = req.valid.body;
  const opportunity = b.opportunityId ? await getVisibleOpportunity(req.user, b.opportunityId) : null;
  const generated = await generateDraft(req.user, { kind: b.kind, opportunity, extraContext: b.extraContext });
  send(res, await saveDraft(req, b.kind, opportunity, generated), { status: 201 });
});

/** "Why this opportunity?" — AI narration of deterministic factors. */
router.post('/explain-match/:id', validate({ params: idParams }), async (req, res) => {
  requireAI();
  const opportunity = await getVisibleOpportunity(req.user, req.valid.params.id);
  const eligibility = checkEligibility(opportunity, req.user.profile);
  const match = scoreOpportunity(opportunity, req.user.profile, { eligibility });
  const result = await explainMatch(req.user, { opportunity, eligibility, match });
  send(res, { ...result, generatedBy: 'ai', basedOn: { eligibilityOverall: eligibility.overall, factors: match.factors } });
});

export default router;
