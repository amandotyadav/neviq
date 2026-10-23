import { Router } from 'express';
import mongoose from 'mongoose';
import { requireAuth, requireRole, canManageCollege } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import {
  adminOpportunityCreateSchema, adminOpportunityPatchSchema, adminVerifySchema,
  announcementCreateSchema, announcementPatchSchema, idParams,
} from '../validators/schemas.js';
import { Opportunity, serializeOpportunity, buildDedupeKey } from '../models/Opportunity.js';
import { Announcement, serializeAnnouncement } from '../models/Announcement.js';
import { College, serializeCollege } from '../models/College.js';
import { SavedOpportunity } from '../models/SavedOpportunity.js';
import { Application } from '../models/Application.js';
import { User } from '../models/User.js';
import { IngestRun } from '../models/IngestRun.js';
import { send } from '../utils/http.js';
import { badRequest, forbidden, notFound } from '../utils/errors.js';

const router = Router();
router.use(requireAuth, requireRole('college_admin', 'platform_admin'));

/** Aggregate counts below this are suppressed to protect individuals. */
const MIN_REPORTABLE = 3;
const suppress = (n) => (n > 0 && n < MIN_REPORTABLE ? { count: null, suppressed: true } : { count: n, suppressed: false });

/** Fields whose change means the listing must be re-verified. */
const FACT_FIELDS = ['title', 'organization', 'sourceUrl', 'applicationUrl', 'deadline', 'applicationOpensAt', 'declaredStatus',
  'eligibleDegrees', 'eligibleYears', 'eligibleBranches', 'requiredSkills', 'minimumCGPA', 'award', 'stipend', 'eligibilityRules',
  'requiredDocuments', 'officialDescription'];

function scopeFilter(user) {
  return user.role === 'platform_admin' ? {} : { collegeId: { $in: user.adminCollegeIds ?? [] } };
}

async function manageableOpportunity(req) {
  const opp = await Opportunity.findById(req.valid.params.id);
  if (!opp) throw notFound('Opportunity not found');
  const allowed = opp.collegeId ? canManageCollege(req.user, opp.collegeId) : req.user.role === 'platform_admin';
  if (!allowed) throw forbidden('You can only manage listings for your own college.');
  return opp;
}

async function manageableAnnouncement(req) {
  const a = await Announcement.findById(req.valid.params.id);
  if (!a) throw notFound('Announcement not found');
  if (!canManageCollege(req.user, a.collegeId)) throw forbidden('You can only manage announcements for your own college.');
  return a;
}

router.get('/colleges', async (req, res) => {
  const filter = req.user.role === 'platform_admin' ? {} : { _id: { $in: req.user.adminCollegeIds ?? [] } };
  const colleges = await College.find(filter).sort({ name: 1 }).limit(200).lean();
  send(res, colleges.map(serializeCollege));
});

// ---- Opportunities ------------------------------------------------------

router.get('/opportunities', async (req, res) => {
  const opps = await Opportunity.find(scopeFilter(req.user)).sort({ updatedAt: -1 }).limit(200).lean();
  send(res, opps.map((o) => serializeOpportunity(o)));
});

router.post('/opportunities', validate({ body: adminOpportunityCreateSchema }), async (req, res) => {
  const b = req.valid.body;
  const collegeId = b.collegeId ?? null;
  if (collegeId) {
    if (!canManageCollege(req.user, collegeId)) throw forbidden('You can only publish for your own college.');
    if (!(await College.exists({ _id: collegeId }))) throw badRequest('College not found');
  } else if (req.user.role !== 'platform_admin') {
    throw forbidden('College admins must publish listings for their own college.');
  }
  const opp = await Opportunity.create({
    ...b,
    applicationUrl: b.applicationUrl || undefined,
    collegeId,
    sourceType: collegeId && req.user.role === 'college_admin' ? 'college_admin' : b.sourceType,
    // New listings always start unverified-by-review; use /verify after checking the source.
    verificationStatus: 'pending',
    dedupeKey: buildDedupeKey({ sourceUrl: b.sourceUrl, title: b.title, collegeId }),
    createdBy: String(req.user._id),
  });
  send(res, serializeOpportunity(opp), { status: 201 });
});

router.patch('/opportunities/:id', validate({ params: idParams, body: adminOpportunityPatchSchema }), async (req, res) => {
  const opp = await manageableOpportunity(req);
  const b = req.valid.body;
  if (b.collegeId !== undefined && String(b.collegeId ?? '') !== String(opp.collegeId ?? '')) {
    throw badRequest('A listing cannot be moved to another college. Create a new listing instead.');
  }
  delete b.collegeId;
  const changedFacts = FACT_FIELDS.some((f) => b[f] !== undefined);
  for (const [key, value] of Object.entries(b)) {
    if (key === 'sourceType' && req.user.role === 'college_admin') continue;
    opp[key] = key === 'applicationUrl' ? value || undefined : value;
  }
  if (changedFacts && opp.verificationStatus === 'verified') {
    opp.verificationStatus = 'pending';
    opp.verificationNotes = 'Facts were edited after verification; re-verify against the official source.';
  }
  if (b.title || b.sourceUrl) opp.dedupeKey = buildDedupeKey({ sourceUrl: opp.sourceUrl, title: opp.title, collegeId: opp.collegeId });
  await opp.save();
  send(res, serializeOpportunity(opp));
});

/** The admin attests that they checked the listing against its official source. */
router.post('/opportunities/:id/verify', validate({ params: idParams, body: adminVerifySchema }), async (req, res) => {
  const opp = await manageableOpportunity(req);
  opp.verificationStatus = 'verified';
  opp.lastVerifiedAt = new Date();
  opp.verifiedBy = `${req.user.role}:${req.user._id}`;
  opp.verificationNotes = req.valid.body.notes ?? `Verified against ${opp.sourceUrl}`;
  await opp.save();
  send(res, serializeOpportunity(opp));
});

// ---- Announcements ------------------------------------------------------

router.get('/announcements', async (req, res) => {
  const filter = req.user.role === 'platform_admin' ? {} : { collegeId: { $in: req.user.adminCollegeIds ?? [] } };
  const items = await Announcement.find(filter).sort({ updatedAt: -1 }).limit(200).lean();
  const colleges = await College.find({ _id: { $in: [...new Set(items.map((a) => String(a.collegeId)))] } }).lean();
  const names = new Map(colleges.map((c) => [String(c._id), c.name]));
  send(res, items.map((a) => serializeAnnouncement(a, names.get(String(a.collegeId)))));
});

router.post('/announcements', validate({ body: announcementCreateSchema }), async (req, res) => {
  const b = req.valid.body;
  if (!canManageCollege(req.user, b.collegeId)) throw forbidden('You can only publish announcements for your own college.');
  const college = await College.findById(b.collegeId).lean();
  if (!college) throw badRequest('College not found');
  if (b.linkedOpportunityId) {
    const linked = await Opportunity.findById(b.linkedOpportunityId).lean();
    if (!linked || (linked.collegeId && String(linked.collegeId) !== String(b.collegeId))) throw badRequest('Linked opportunity is not available to this college');
  }
  const a = await Announcement.create({
    ...b,
    sourceUrl: b.sourceUrl || undefined,
    publishedAt: b.status === 'published' ? new Date() : null,
    createdBy: req.user._id,
    updatedBy: req.user._id,
    publisherName: req.user.name,
  });
  send(res, serializeAnnouncement(a, college.name), { status: 201 });
});

router.patch('/announcements/:id', validate({ params: idParams, body: announcementPatchSchema }), async (req, res) => {
  const a = await manageableAnnouncement(req);
  const b = req.valid.body;
  for (const [key, value] of Object.entries(b)) a[key] = key === 'sourceUrl' ? value || undefined : value;
  if (b.status === 'published' && !a.publishedAt) a.publishedAt = new Date();
  a.updatedBy = req.user._id;
  await a.save();
  const college = await College.findById(a.collegeId).lean();
  send(res, serializeAnnouncement(a, college?.name));
});

// ---- Automated refresh history (platform admins) ---------------------------

router.get('/ingest-runs', requireRole('platform_admin'), async (_req, res) => {
  send(res, await IngestRun.find().sort({ startedAt: -1 }).limit(20).lean());
});

// ---- Metrics (aggregate only, computed from real records) -----------------

router.get('/metrics', async (req, res) => {
  const collegeIds = req.user.role === 'platform_admin'
    ? (await College.find().select('_id').lean()).map((c) => c._id)
    : (req.user.adminCollegeIds ?? []).map((id) => new mongoose.Types.ObjectId(String(id)));

  const opps = await Opportunity.find({ collegeId: { $in: collegeIds } }).select('title verificationStatus status').lean();
  const oppIds = opps.map((o) => o._id);
  const [saves, tracked, students, announcements] = await Promise.all([
    SavedOpportunity.aggregate([{ $match: { opportunityId: { $in: oppIds } } }, { $group: { _id: '$opportunityId', n: { $sum: 1 } } }]),
    Application.aggregate([{ $match: { opportunityId: { $in: oppIds } } }, { $group: { _id: '$opportunityId', n: { $sum: 1 } } }]),
    User.countDocuments({ 'profile.collegeId': { $in: collegeIds }, role: 'student' }),
    Announcement.aggregate([{ $match: { collegeId: { $in: collegeIds } } }, { $group: { _id: '$status', n: { $sum: 1 } } }]),
  ]);
  const savesBy = new Map(saves.map((s) => [String(s._id), s.n]));
  const trackedBy = new Map(tracked.map((s) => [String(s._id), s.n]));

  send(res, {
    generatedAt: new Date().toISOString(),
    note: `Counts below ${MIN_REPORTABLE} are hidden to protect individual students. No individual student data is shown.`,
    studentsOnNaviq: suppress(students),
    announcements: Object.fromEntries(['draft', 'published', 'archived'].map((s) => [s, announcements.find((x) => x._id === s)?.n ?? 0])),
    listings: opps.map((o) => ({
      opportunityId: String(o._id),
      title: o.title,
      status: o.status,
      verificationStatus: o.verificationStatus,
      saves: suppress(savesBy.get(String(o._id)) ?? 0),
      tracked: suppress(trackedBy.get(String(o._id)) ?? 0),
    })),
  });
});

export default router;
