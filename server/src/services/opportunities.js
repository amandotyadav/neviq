import { Opportunity, computeAvailability, serializeOpportunity } from '../models/Opportunity.js';
import { SavedOpportunity } from '../models/SavedOpportunity.js';
import { Application } from '../models/Application.js';
import { checkEligibility, normalizeDegree } from '../eligibility/engine.js';
import { scoreOpportunity, rankMatches } from '../matching/engine.js';
import { assertObjectId, escapeRegex, paginate } from '../utils/http.js';
import { notFound } from '../utils/errors.js';

const MAX_CANDIDATES = 500;

/**
 * Students see published public listings plus published listings for their
 * own college. Nothing else.
 */
export function visibilityFilter(user) {
  const collegeId = user.profile?.collegeId ?? null;
  return {
    status: 'published',
    $or: collegeId ? [{ collegeId: null }, { collegeId }] : [{ collegeId: null }],
  };
}

export async function getVisibleOpportunity(user, id) {
  assertObjectId(id, 'Opportunity');
  const opp = await Opportunity.findOne({ _id: id, ...visibilityFilter(user) }).lean();
  if (!opp) throw notFound('Opportunity not found');
  return opp;
}

export async function userStateFor(user, opportunityIds) {
  const [saved, apps] = await Promise.all([
    SavedOpportunity.find({ userId: user._id, opportunityId: { $in: opportunityIds } }).select('opportunityId').lean(),
    Application.find({ userId: user._id, opportunityId: { $in: opportunityIds } }).select('opportunityId status archived').lean(),
  ]);
  return {
    saved: new Set(saved.map((s) => String(s.opportunityId))),
    apps: new Map(apps.map((a) => [String(a.opportunityId), { id: String(a._id), status: a.status, archived: a.archived }])),
  };
}

/** Builds the list item returned to clients, with match explanation. */
export function presentWithMatch(opp, user, state, now = new Date()) {
  const eligibility = checkEligibility(opp, user.profile, { now });
  const match = scoreOpportunity(opp, user.profile, { now, eligibility });
  const id = String(opp._id);
  return {
    opportunity: opp,
    match,
    item: serializeOpportunity(opp, {
      match: {
        score: match.score,
        scoreLabel: match.scoreLabel,
        eligibilityOverall: match.eligibilityOverall,
        hardBlocked: match.hardBlocked,
        audienceRestricted: match.audienceRestricted,
        confirmedFit: match.confirmedFit,
        factors: match.factors,
      },
      isSaved: state.saved.has(id),
      tracked: state.apps.get(id) ?? null,
    }),
  };
}

export async function searchOpportunities(user, q, now = new Date()) {
  const filter = { ...visibilityFilter(user) };
  const and = [];
  if (q.type) filter.opportunityType = q.type;
  if (q.workMode) filter.workMode = q.workMode;
  if (q.verifiedOnly) filter.verificationStatus = 'verified';
  if (q.campusOnly) {
    filter.collegeId = user.profile?.collegeId ?? '000000000000000000000000';
    delete filter.$or;
  }
  if (q.q) {
    const rx = new RegExp(escapeRegex(q.q), 'i');
    and.push({ $or: [{ title: rx }, { organization: rx }, { tags: rx }, { officialDescription: rx }, { requiredSkills: rx }] });
  }
  if (q.location) {
    const rx = new RegExp(escapeRegex(q.location), 'i');
    and.push({ $or: [{ 'location.city': rx }, { 'location.state': rx }, { 'location.description': rx }, { 'location.isNationwide': true }] });
  }
  if (q.skills?.length) {
    const rxs = q.skills.map((s) => new RegExp(`^${escapeRegex(s)}$`, 'i'));
    and.push({ $or: [{ requiredSkills: { $in: rxs } }, { preferredSkills: { $in: rxs } }, { tags: { $in: rxs } }] });
  }
  if (q.deadlineWithinDays) {
    filter.deadline = { $gte: now, $lte: new Date(now.getTime() + q.deadlineWithinDays * 86400000) };
  }
  if (and.length) filter.$and = and;

  let docs = await Opportunity.find(filter).limit(MAX_CANDIDATES).lean();

  // Derived-state filters (availability depends on "now").
  docs = docs.filter((o) => {
    const availability = computeAvailability(o, now);
    if (q.availability) return availability === q.availability;
    return q.includeClosed ? true : availability !== 'closed';
  });
  if (q.degree) {
    const d = normalizeDegree(q.degree);
    docs = docs.filter((o) => !o.eligibleDegrees?.length || o.eligibleDegrees.map(normalizeDegree).includes(d));
  }
  if (q.year) docs = docs.filter((o) => !o.eligibleYears?.length || o.eligibleYears.includes(q.year));

  const state = await userStateFor(user, docs.map((d) => d._id));
  let rows = docs.map((o) => presentWithMatch(o, user, state, now));

  if (q.sort === 'deadline') {
    rows.sort((a, b) => (a.opportunity.deadline ? new Date(a.opportunity.deadline) : Infinity) - (b.opportunity.deadline ? new Date(b.opportunity.deadline) : Infinity));
  } else if (q.sort === 'recent') {
    rows.sort((a, b) => new Date(b.opportunity.updatedAt) - new Date(a.opportunity.updatedAt));
  } else {
    rows = rankMatches(rows);
  }

  const { items, meta } = paginate(rows, q.page, q.limit);
  return { items: items.map((r) => r.item), meta };
}

/**
 * Recommendations that claim current availability: verified, not closed,
 * not hard-blocked by a mandatory criterion.
 */
export async function recommendedMatches(user, { limit = 10, now = new Date() } = {}) {
  const docs = await Opportunity.find({ ...visibilityFilter(user), verificationStatus: 'verified' }).limit(MAX_CANDIDATES).lean();
  const open = docs.filter((o) => ['open', 'upcoming'].includes(computeAvailability(o, now)));
  const state = await userStateFor(user, open.map((d) => d._id));
  const ranked = rankMatches(open.map((o) => presentWithMatch(o, user, state, now)));
  return {
    items: ranked.filter((r) => !r.match.hardBlocked && !r.match.audienceRestricted && r.match.confirmedFit).slice(0, limit).map((r) => r.item),
    excludedIneligible: ranked.filter((r) => r.match.hardBlocked).length,
    excludedRestricted: ranked.filter((r) => !r.match.hardBlocked && r.match.audienceRestricted).length,
    excludedUnconfirmed: ranked.filter((r) => !r.match.hardBlocked && !r.match.audienceRestricted && !r.match.confirmedFit).length,
  };
}
