import { z } from 'zod';
import { OPPORTUNITY_TYPES, SOURCE_TYPES, DECLARED_STATUSES, OPP_WORK_MODES, RULE_KINDS } from '../models/Opportunity.js';
import { APPLICATION_STATUSES } from '../models/Application.js';
import { MILESTONE_STATUSES, PRIORITIES } from '../models/Roadmap.js';
import { ANNOUNCEMENT_CATEGORIES } from '../models/Announcement.js';
import { DRAFT_KINDS } from '../models/Draft.js';

const objectId = z.string().regex(/^[a-f\d]{24}$/i, 'Invalid id');
const str = (max) => z.string().trim().max(max);
const httpsUrl = z.string().trim().url().max(500).refine((u) => /^https?:\/\//i.test(u), 'Must be an http(s) URL');
// null must be tried first: z.coerce.date() turns null into 1970-01-01.
const optionalDate = z.union([z.null(), z.coerce.date()]).optional();
const tagList = (max = 30, len = 60) => z.array(str(len).min(1)).max(max);

// ---- Auth ---------------------------------------------------------------

export const registerSchema = z.object({
  name: str(100).min(1, 'Name is required'),
  email: z.string().trim().toLowerCase().email('Enter a valid email address').max(254),
  password: z.string().min(8, 'Password must be at least 8 characters').max(128),
}).strict();

export const loginSchema = z.object({
  email: z.string().trim().toLowerCase().email().max(254),
  password: z.string().min(1).max(128),
});

// ---- Profile ------------------------------------------------------------

const projectInput = z.object({
  title: str(120).min(1),
  description: str(1000).optional(),
  skills: tagList(15, 40).optional(),
  url: z.union([httpsUrl, z.literal('')]).optional(),
});

const experienceInput = z.object({
  role: str(120).min(1),
  organization: str(120).min(1),
  startDate: optionalDate,
  endDate: optionalDate,
  description: str(1000).optional(),
});

/** `role`, `adminCollegeIds`, `email`, `tokenVersion` are deliberately absent. */
export const profilePatchSchema = z.object({
  name: str(100).min(1).optional(),
  profile: z.object({
    collegeId: z.union([objectId, z.null()]).optional(),
    customCollegeName: str(160).min(2).optional(),
    degree: str(60).optional(),
    branch: str(80).optional(),
    currentYear: z.union([z.number().int().min(1).max(6), z.null()]).optional(),
    semester: z.union([z.number().int().min(1).max(12), z.null()]).optional(),
    graduationYear: z.union([z.number().int().min(2000).max(2100), z.null()]).optional(),
    cgpa: z.union([z.number().min(0).max(10), z.null()]).optional(),
    skills: tagList(40, 40).optional(),
    interests: tagList(20, 60).optional(),
    careerGoal: str(300).optional(),
    headline: str(160).optional(),
    projects: z.array(projectInput).max(20).optional(),
    experience: z.array(experienceInput).max(20).optional(),
    achievements: z.array(str(300).min(1)).max(20).optional(),
    preferredLocations: tagList(10, 60).optional(),
    workModes: z.array(z.enum(['remote', 'hybrid', 'onsite'])).max(3).optional(),
    homeState: z.union([str(60), z.null()]).optional(),
    annualFamilyIncomeINR: z.union([z.number().min(0).max(1e9), z.null()]).optional(),
    links: z.object({
      github: z.union([httpsUrl, z.literal('')]).optional(),
      linkedin: z.union([httpsUrl, z.literal('')]).optional(),
      portfolio: z.union([httpsUrl, z.literal('')]).optional(),
    }).optional(),
  }).optional(),
  notificationPrefs: z.object({
    deadlineReminders: z.boolean().optional(),
    reminderDaysBefore: z.number().int().min(0).max(30).optional(),
    campusAnnouncements: z.boolean().optional(),
  }).optional(),
  completeOnboarding: z.boolean().optional(),
});

export const deleteAccountSchema = z.object({ password: z.string().min(1).max(128) });

// ---- Opportunities ------------------------------------------------------

const csv = z.string().trim().max(300).transform((s) => s.split(',').map((x) => x.trim()).filter(Boolean));

export const opportunityQuerySchema = z.object({
  q: str(120).optional(),
  type: z.enum(OPPORTUNITY_TYPES).optional(),
  workMode: z.enum(['remote', 'hybrid', 'onsite']).optional(),
  location: str(60).optional(),
  degree: str(60).optional(),
  year: z.coerce.number().int().min(1).max(6).optional(),
  skills: csv.optional(),
  availability: z.enum(DECLARED_STATUSES).optional(),
  includeClosed: z.enum(['true', 'false']).transform((v) => v === 'true').optional(),
  verifiedOnly: z.enum(['true', 'false']).transform((v) => v === 'true').optional(),
  deadlineWithinDays: z.coerce.number().int().min(1).max(365).optional(),
  campusOnly: z.enum(['true', 'false']).transform((v) => v === 'true').optional(),
  sort: z.enum(['relevance', 'deadline', 'recent']).default('relevance'),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(50).default(20),
});

export const idParams = z.object({ id: objectId });

export const eligibilityCheckSchema = z.object({
  opportunityId: objectId,
  declarations: z.record(z.string().max(60), z.boolean()).optional(),
});

// ---- Applications -------------------------------------------------------

export const applicationCreateSchema = z.object({
  opportunityId: objectId.nullish(),
  title: str(200).min(1).optional(),
  organization: str(160).optional(),
  applicationUrl: z.union([httpsUrl, z.literal('')]).optional(),
  status: z.enum(APPLICATION_STATUSES).default('interested'),
  notes: str(4000).optional(),
  deadline: optionalDate,
  nextAction: str(300).optional(),
  nextActionDue: optionalDate,
  appliedAt: optionalDate,
}).refine((v) => v.opportunityId || v.title, { message: 'Provide an opportunityId or a title', path: ['title'] });

export const applicationPatchSchema = z.object({
  title: str(200).min(1).optional(),
  organization: str(160).optional(),
  applicationUrl: z.union([httpsUrl, z.literal('')]).optional(),
  status: z.enum(APPLICATION_STATUSES).optional(),
  notes: str(4000).optional(),
  deadline: optionalDate,
  nextAction: z.union([str(300), z.null()]).optional(),
  nextActionDue: optionalDate,
  appliedAt: optionalDate,
  archived: z.boolean().optional(),
});

export const applicationQuerySchema = z.object({
  archived: z.enum(['true', 'false']).transform((v) => v === 'true').default('false'),
  status: z.enum(APPLICATION_STATUSES).optional(),
});

// ---- Roadmap ------------------------------------------------------------

export const roadmapGenerateSchema = z.object({
  goal: str(300).min(3, 'Describe your goal in a few words'),
  opportunityId: objectId.nullish(),
});

export const milestonePatchSchema = z.object({
  status: z.enum(MILESTONE_STATUSES).optional(),
  priority: z.enum(PRIORITIES).optional(),
  order: z.number().int().min(0).max(1000).optional(),
  targetDate: optionalDate,
  title: str(160).min(1).optional(),
});

export const milestoneCreateSchema = z.object({
  goal: str(300).min(3).optional(),
  title: str(160).min(1),
  purpose: str(600).optional(),
  steps: z.array(str(300).min(1)).max(15).default([]),
  skills: tagList(10, 40).default([]),
  priority: z.enum(PRIORITIES).default('medium'),
  targetDate: optionalDate,
});

export const milestoneParams = z.object({ milestoneId: objectId });

// ---- AI -----------------------------------------------------------------

export const chatSchema = z.object({
  messages: z.array(z.object({
    role: z.enum(['user', 'assistant']),
    content: str(4000).min(1),
  })).min(1).max(30),
  contextOpportunityId: objectId.nullish(),
});

export const draftEmailSchema = z.object({
  opportunityId: objectId,
  recipientName: str(100).optional(),
  tone: z.enum(['formal', 'warm', 'concise']).default('formal'),
  extraContext: str(600).optional(),
});

export const resumeSchema = z.object({
  kind: z.enum(['resume', 'cover_letter', 'resume_summary']),
  opportunityId: objectId.nullish(),
  extraContext: str(600).optional(),
});

export const draftPatchSchema = z.object({
  title: str(200).optional(),
  subject: str(300).optional(),
  body: z.string().min(1).max(20000).optional(),
  markReviewed: z.boolean().optional(),
});

export const draftCreateSchema = z.object({
  kind: z.enum(DRAFT_KINDS),
  opportunityId: objectId.nullish(),
  title: str(200).optional(),
  subject: str(300).optional(),
  body: z.string().min(1).max(20000),
});

// ---- Admin --------------------------------------------------------------

const moneyInput = z.object({
  amount: z.union([z.number().min(0), z.null()]).optional(),
  currency: z.string().length(3).default('INR'),
  period: z.union([z.enum(['per_year', 'per_month', 'one_time', 'total']), z.null()]).optional(),
  description: str(500).optional(),
});

const ruleInput = z.object({
  key: z.string().trim().regex(/^[a-z0-9_]{1,60}$/, 'Use lowercase letters, numbers and underscores'),
  kind: z.enum(RULE_KINDS),
  label: str(300).min(1),
  mandatory: z.boolean().default(true),
  values: z.array(str(80)).max(40).default([]),
  numberValue: z.number().optional(),
  sourceExcerpt: str(600).optional(),
  note: str(400).optional(),
  restrictsAudience: z.boolean().default(false),
});

const opportunityFields = {
  title: str(200).min(3),
  organization: str(160).min(2),
  opportunityType: z.enum(OPPORTUNITY_TYPES),
  officialDescription: str(4000).optional(),
  summary: str(1500).optional(),
  sourceUrl: httpsUrl,
  applicationUrl: z.union([httpsUrl, z.literal('')]).optional(),
  sourceType: z.enum(SOURCE_TYPES).default('college_admin'),
  declaredStatus: z.enum(DECLARED_STATUSES).default('unknown'),
  applicationOpensAt: optionalDate,
  deadline: optionalDate,
  deadlineNote: str(300).optional(),
  eligibleDegrees: tagList(20, 60).default([]),
  eligibleYears: z.array(z.number().int().min(1).max(6)).max(6).default([]),
  eligibleBranches: tagList(30, 80).default([]),
  requiredSkills: tagList(20, 40).default([]),
  preferredSkills: tagList(20, 40).default([]),
  minimumCGPA: z.union([z.number().min(0).max(10), z.null()]).optional(),
  location: z.object({
    city: str(60).optional(),
    state: str(60).optional(),
    country: str(60).optional(),
    isNationwide: z.boolean().optional(),
    description: str(200).optional(),
  }).optional(),
  workMode: z.enum(OPP_WORK_MODES).default('unknown'),
  award: moneyInput.nullable().optional(),
  stipend: moneyInput.nullable().optional(),
  duration: str(120).optional(),
  eligibilityRules: z.array(ruleInput).max(30).default([]),
  requiredDocuments: z.array(str(200).min(1)).max(30).default([]),
  tags: tagList(20, 40).default([]),
  collegeId: z.union([objectId, z.null()]).optional(),
  status: z.enum(['draft', 'published', 'archived']).default('draft'),
};

export const adminOpportunityCreateSchema = z.object(opportunityFields);
export const adminOpportunityPatchSchema = z.object(
  Object.fromEntries(Object.entries(opportunityFields).map(([k, v]) => [k, v.optional()])),
);

export const adminVerifySchema = z.object({
  sourceConfirmed: z.literal(true, { message: 'Confirm you checked the official source' }),
  notes: str(1000).optional(),
});

export const announcementCreateSchema = z.object({
  collegeId: objectId,
  title: str(160).min(3),
  body: str(5000).min(3),
  category: z.enum(ANNOUNCEMENT_CATEGORIES).default('general'),
  sourceUrl: z.union([httpsUrl, z.literal('')]).optional(),
  linkedOpportunityId: objectId.optional(),
  status: z.enum(['draft', 'published', 'archived']).default('draft'),
  expiresAt: optionalDate,
});

export const announcementPatchSchema = z.object({
  title: str(160).min(3).optional(),
  body: str(5000).min(3).optional(),
  category: z.enum(ANNOUNCEMENT_CATEGORIES).optional(),
  sourceUrl: z.union([httpsUrl, z.literal('')]).optional(),
  status: z.enum(['draft', 'published', 'archived']).optional(),
  expiresAt: optionalDate,
});

export const collegeQuerySchema = z.object({ q: str(80).optional() });
