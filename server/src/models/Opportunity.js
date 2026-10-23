import mongoose from 'mongoose';

const { Schema } = mongoose;

export const OPPORTUNITY_TYPES = ['internship', 'scholarship', 'fellowship', 'research', 'competition', 'hackathon', 'job', 'program'];
export const SOURCE_TYPES = ['government_portal', 'official_org_site', 'employer_career_page', 'university_site', 'college_admin'];
export const VERIFICATION_STATUSES = ['verified', 'pending', 'needs_review', 'unverified'];
export const DECLARED_STATUSES = ['open', 'closed', 'upcoming', 'unknown'];
export const OPP_WORK_MODES = ['remote', 'hybrid', 'onsite', 'not_applicable', 'unknown'];
export const RULE_KINDS = [
  'degree_in',
  'branch_in',
  'year_in',
  'graduation_year_in',
  'min_cgpa',
  'max_family_income',
  'home_state_in',
  'skills_all',
  'skills_any',
  'self_declared',
];

/** A single structured eligibility criterion extracted from the source. */
const ruleSchema = new Schema(
  {
    key: { type: String, required: true, trim: true, maxlength: 60 },
    kind: { type: String, enum: RULE_KINDS, required: true },
    label: { type: String, required: true, trim: true, maxlength: 300 },
    mandatory: { type: Boolean, default: true },
    values: [{ type: String, trim: true }],
    numberValue: Number,
    sourceExcerpt: { type: String, trim: true, maxlength: 600 },
    note: { type: String, trim: true, maxlength: 400 },
    // True when the criterion limits who the listing is for (e.g. girl
    // students, students with a disability, existing awardees). Naviq never
    // infers these, so such listings are not recommended until confirmed.
    restrictsAudience: { type: Boolean, default: false },
  },
  { _id: false },
);

/** Money is stored with its currency and period. Unknown stays null. */
const moneySchema = new Schema(
  {
    amount: { type: Number, min: 0, default: null },
    currency: { type: String, default: 'INR' },
    period: { type: String, enum: ['per_year', 'per_month', 'one_time', 'total', null], default: null },
    description: { type: String, trim: true, maxlength: 500 },
  },
  { _id: false },
);

const opportunitySchema = new Schema(
  {
    title: { type: String, required: true, trim: true, maxlength: 200 },
    organization: { type: String, required: true, trim: true, maxlength: 160 },
    opportunityType: { type: String, enum: OPPORTUNITY_TYPES, required: true },
    // Facts taken from the official source.
    officialDescription: { type: String, trim: true, maxlength: 4000 },
    // Editor- or AI-written summary, labelled separately in the client.
    summary: { type: String, trim: true, maxlength: 1500 },
    summarySource: { type: String, enum: ['editor', 'ai', null], default: null },

    sourceUrl: { type: String, required: true, trim: true, maxlength: 500 },
    applicationUrl: { type: String, trim: true, maxlength: 500 },
    additionalSources: [{ label: String, url: String }],
    sourceType: { type: String, enum: SOURCE_TYPES, required: true },

    verificationStatus: { type: String, enum: VERIFICATION_STATUSES, default: 'pending' },
    lastVerifiedAt: { type: Date, default: null },
    verifiedBy: { type: String, trim: true },
    verificationNotes: { type: String, trim: true, maxlength: 1000 },
    lastSourceCheck: {
      checkedAt: Date,
      httpStatus: Number,
      ok: Boolean,
    },

    declaredStatus: { type: String, enum: DECLARED_STATUSES, default: 'unknown' },
    applicationOpensAt: { type: Date, default: null },
    deadline: { type: Date, default: null },
    deadlineNote: { type: String, trim: true, maxlength: 300 },

    eligibleDegrees: [{ type: String, trim: true }],
    eligibleYears: [{ type: Number, min: 1, max: 6 }],
    eligibleBranches: [{ type: String, trim: true }],
    requiredSkills: [{ type: String, trim: true }],
    preferredSkills: [{ type: String, trim: true }],
    minimumCGPA: { type: Number, min: 0, max: 10, default: null },

    location: {
      city: String,
      state: String,
      country: { type: String, default: 'India' },
      isNationwide: { type: Boolean, default: false },
      description: String,
    },
    workMode: { type: String, enum: OPP_WORK_MODES, default: 'unknown' },
    award: { type: moneySchema, default: null },
    stipend: { type: moneySchema, default: null },
    duration: { type: String, trim: true, maxlength: 120 },

    eligibilityRules: [ruleSchema],
    requiredDocuments: [{ type: String, trim: true, maxlength: 200 }],
    tags: [{ type: String, trim: true, lowercase: true }],

    // null collegeId = public listing; otherwise visible only to that college.
    collegeId: { type: Schema.Types.ObjectId, ref: 'College', default: null },
    status: { type: String, enum: ['draft', 'published', 'archived'], default: 'published' },
    dedupeKey: { type: String, required: true, unique: true },
    // Stable id from an automated source (e.g. "nsp:aicte-pragati-…"); lets daily refreshes update, not duplicate.
    externalId: { type: String, unique: true, sparse: true },
    datesRefreshedAt: { type: Date, default: null },
    createdBy: { type: String, trim: true },
  },
  { timestamps: true },
);

opportunitySchema.index({ status: 1, collegeId: 1, opportunityType: 1 });
opportunitySchema.index({ deadline: 1 });
opportunitySchema.index({ tags: 1 });

/** Normalized URL + title identifies the same listing across imports. */
export function buildDedupeKey({ sourceUrl, title, collegeId }) {
  const url = String(sourceUrl).toLowerCase().replace(/^https?:\/\/(www\.)?/, '').replace(/[#?].*$/, '').replace(/\/+$/, '');
  const t = String(title).toLowerCase().replace(/[^a-z0-9]+/g, '-');
  return `${collegeId ? `${collegeId}:` : ''}${url}|${t}`;
}

export const STALE_AFTER_DAYS = 30;

/**
 * Availability is derived from explicit dates where available. A deadline in
 * the past always wins over a declared "open" status.
 */
export function computeAvailability(opp, now = new Date()) {
  if (opp.deadline && new Date(opp.deadline) < now) return 'closed';
  if (opp.declaredStatus === 'closed') return 'closed';
  if (opp.applicationOpensAt && new Date(opp.applicationOpensAt) > now) return 'upcoming';
  return opp.declaredStatus ?? 'unknown';
}

export function isStale(opp, now = new Date()) {
  if (!opp.lastVerifiedAt) return true;
  return now - new Date(opp.lastVerifiedAt) > STALE_AFTER_DAYS * 86400000;
}

export const Opportunity = mongoose.model('Opportunity', opportunitySchema);

export function serializeOpportunity(o, extra = {}) {
  const now = new Date();
  return {
    id: String(o._id),
    title: o.title,
    organization: o.organization,
    opportunityType: o.opportunityType,
    officialDescription: o.officialDescription ?? null,
    summary: o.summary ?? null,
    summarySource: o.summarySource ?? null,
    sourceUrl: o.sourceUrl,
    applicationUrl: o.applicationUrl ?? null,
    additionalSources: (o.additionalSources ?? []).map((s) => ({ label: s.label, url: s.url })),
    sourceType: o.sourceType,
    verificationStatus: o.verificationStatus,
    lastVerifiedAt: o.lastVerifiedAt ?? null,
    datesRefreshedAt: o.datesRefreshedAt ?? null,
    verificationNotes: o.verificationNotes ?? null,
    isStale: isStale(o, now),
    availability: computeAvailability(o, now),
    applicationOpensAt: o.applicationOpensAt ?? null,
    deadline: o.deadline ?? null,
    deadlineNote: o.deadlineNote ?? null,
    eligibleDegrees: o.eligibleDegrees ?? [],
    eligibleYears: o.eligibleYears ?? [],
    eligibleBranches: o.eligibleBranches ?? [],
    requiredSkills: o.requiredSkills ?? [],
    preferredSkills: o.preferredSkills ?? [],
    minimumCGPA: o.minimumCGPA ?? null,
    location: o.location ?? null,
    workMode: o.workMode,
    award: o.award?.amount != null || o.award?.description ? o.award : null,
    stipend: o.stipend?.amount != null || o.stipend?.description ? o.stipend : null,
    duration: o.duration ?? null,
    eligibilityRules: (o.eligibilityRules ?? []).map((r) => ({
      key: r.key,
      kind: r.kind,
      label: r.label,
      mandatory: r.mandatory,
      values: r.values ?? [],
      numberValue: r.numberValue ?? null,
      sourceExcerpt: r.sourceExcerpt ?? null,
      note: r.note ?? null,
      restrictsAudience: Boolean(r.restrictsAudience),
    })),
    requiredDocuments: o.requiredDocuments ?? [],
    tags: o.tags ?? [],
    collegeId: o.collegeId ? String(o.collegeId) : null,
    status: o.status,
    updatedAt: o.updatedAt,
    ...extra,
  };
}
