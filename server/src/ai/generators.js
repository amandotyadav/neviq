import { z } from 'zod';
import { requireAI } from './provider.js';
import { profileForModel, opportunityForModel, UNTRUSTED_NOTICE } from './context.js';
import { AppError } from '../utils/errors.js';

const invalid = () => new AppError(502, 'AI_INVALID_OUTPUT', 'Saathi returned an answer in an unexpected format. Please try again.');

// ---- Roadmap ------------------------------------------------------------

const ROADMAP_JSON_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['summary', 'milestones'],
  properties: {
    summary: { type: 'string' },
    milestones: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['title', 'purpose', 'steps', 'skills', 'effortEstimate', 'priority', 'prerequisites', 'verifiedResourceIds', 'suggestedResources', 'projectIdeas'],
        properties: {
          title: { type: 'string' },
          purpose: { type: 'string' },
          steps: { type: 'array', items: { type: 'string' } },
          skills: { type: 'array', items: { type: 'string' } },
          effortEstimate: { type: 'string' },
          priority: { type: 'string', enum: ['high', 'medium', 'low'] },
          prerequisites: { type: 'array', items: { type: 'string' } },
          verifiedResourceIds: { type: 'array', items: { type: 'string' } },
          suggestedResources: {
            type: 'array',
            items: { type: 'object', additionalProperties: false, required: ['title', 'note'], properties: { title: { type: 'string' }, note: { type: 'string' } } },
          },
          projectIdeas: { type: 'array', items: { type: 'string' } },
        },
      },
    },
  },
};

const roadmapOutput = z.object({
  summary: z.string().min(1).max(1500),
  milestones: z.array(z.object({
    title: z.string().min(1).max(160),
    purpose: z.string().max(600),
    steps: z.array(z.string().max(300)).max(10),
    skills: z.array(z.string().max(40)).max(10),
    effortEstimate: z.string().max(120),
    priority: z.enum(['high', 'medium', 'low']),
    prerequisites: z.array(z.string().max(160)).max(6),
    verifiedResourceIds: z.array(z.string()).max(6),
    suggestedResources: z.array(z.object({ title: z.string().max(160), note: z.string().max(300) })).max(5),
    projectIdeas: z.array(z.string().max(300)).max(4),
  })).min(2).max(8),
});

export async function generateRoadmap(user, { goal, opportunity, eligibility, resources }) {
  const ai = requireAI();
  const catalog = resources.map((r) => ({ id: String(r._id), title: r.title, provider: r.provider, skills: r.skills }));
  const instructions = `You design practical, honest learning roadmaps for Indian college students.
- Base the plan only on the student's profile and goal below. Do not assume skills, grades, or experience they have not listed.
- Produce 3 to 6 milestones in a sensible order. Each needs concrete action steps the student can start this week.
- effortEstimate must be a rough range such as "4–6 hours/week for 3 weeks". It is an estimate.
- For verifiedResourceIds use ONLY ids from the provided resource catalog. Never invent URLs or ids.
- suggestedResources are optional free-text ideas without links (they will be labelled unverified).
- If a target opportunity is given, address its unmet or unknown criteria and required skills directly.
- ${UNTRUSTED_NOTICE}`;
  const input = JSON.stringify({
    goal,
    student: profileForModel(user, { includeName: 'none' }),
    targetOpportunity: opportunity ? opportunityForModel(opportunity) : null,
    eligibilityGaps: eligibility ? eligibility.criteria.filter((c) => c.status !== 'met').map((c) => ({ requirement: c.requirement, status: c.status })) : [],
    resourceCatalog: catalog,
  });

  const raw = await ai.structured({ instructions, input, name: 'naviq_roadmap', schema: ROADMAP_JSON_SCHEMA, maxOutputTokens: 4000 });
  const parsed = roadmapOutput.safeParse(raw);
  if (!parsed.success) throw invalid();
  const allowed = new Set(catalog.map((c) => c.id));
  return {
    model: ai.model,
    summary: parsed.data.summary,
    milestones: parsed.data.milestones.map((m, i) => ({
      ...m,
      order: i,
      verifiedResourceIds: m.verifiedResourceIds.filter((id) => allowed.has(id)),
      source: 'ai',
    })),
  };
}

// ---- Drafts -------------------------------------------------------------

const DRAFT_JSON_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['subject', 'body', 'missingInformation'],
  properties: {
    subject: { type: 'string' },
    body: { type: 'string' },
    missingInformation: { type: 'array', items: { type: 'string' } },
  },
};

const draftOutput = z.object({
  subject: z.string().max(300),
  body: z.string().min(1).max(20000),
  missingInformation: z.array(z.string().max(300)).max(15),
});

const KIND_GUIDE = {
  email: 'a short, professional application or enquiry email (120–220 words). Include a clear subject line.',
  cover_letter: 'a one-page cover letter (250–400 words). Subject should be "Cover letter – <opportunity title>".',
  resume: 'a plain-text resume with sections: Summary, Education, Skills, Projects, Experience, Achievements, Links. Omit empty sections. Subject should be "Resume – <student name>".',
  resume_summary: 'a 2–3 sentence resume summary. Subject should be "Resume summary".',
};

export async function generateDraft(user, { kind, opportunity, tone = 'formal', recipientName, extraContext }) {
  const ai = requireAI();
  const instructions = `You help Indian college students write application material. Write ${KIND_GUIDE[kind]}
Absolute rules:
- Use ONLY facts present in the student data. Never invent qualifications, CGPA, marks, experience, skills, projects, awards, dates, or contact details.
- If something useful is missing, insert a visible placeholder like [ADD: your expected graduation month] and list it in missingInformation.
- Facts about the opportunity must come only from the opportunity data. Do not claim any partnership or prior contact.
- Tone: ${tone}. Write in clear Indian English. No emojis.
- The student will review and edit this before using it. Do not say it has been sent.
- ${UNTRUSTED_NOTICE}`;
  const input = JSON.stringify({
    student: { ...profileForModel(user, { includeName: 'full' }), email: kind === 'email' || kind === 'resume' ? user.email : undefined },
    opportunity: opportunity ? opportunityForModel(opportunity) : null,
    recipientName: recipientName ?? null,
    studentNotes: extraContext ?? null,
  });

  const raw = await ai.structured({ instructions, input, name: 'naviq_draft', schema: DRAFT_JSON_SCHEMA, maxOutputTokens: kind === 'resume' ? 3000 : 1500 });
  const parsed = draftOutput.safeParse(raw);
  if (!parsed.success) throw invalid();

  const { subject, body } = parsed.data;
  const missing = new Set(parsed.data.missingInformation);
  for (const m of body.matchAll(/\[ADD:\s*([^\]]+)\]/g)) missing.add(m[1].trim());
  // Guard: flag CGPA mentions when the profile has no CGPA.
  if (user.profile?.cgpa == null && /\bcgpa\b/i.test(body) && !/\[ADD:[^\]]*cgpa/i.test(body)) {
    missing.add('The draft mentions CGPA, but your profile has none. Verify or remove it.');
  }
  return { model: ai.model, subject, body, missingInformation: [...missing] };
}

// ---- Match explanation ---------------------------------------------------

const EXPLAIN_JSON_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['explanation', 'nextSteps'],
  properties: { explanation: { type: 'string' }, nextSteps: { type: 'array', items: { type: 'string' } } },
};

export async function explainMatch(user, { opportunity, eligibility, match }) {
  const ai = requireAI();
  const instructions = `Explain to a student, in 3–5 sentences, why this opportunity does or does not fit them.
Use ONLY the deterministic match factors and eligibility results provided. Do not add new criteria, do not change any status, and do not call it an official decision.
Then give 1–3 concrete next steps. ${UNTRUSTED_NOTICE}`;
  const input = JSON.stringify({
    student: profileForModel(user),
    opportunity: opportunityForModel(opportunity),
    eligibilityOverall: eligibility.overall,
    criteria: eligibility.criteria.map((c) => ({ requirement: c.requirement, status: c.status, explanation: c.explanation })),
    caveats: eligibility.caveats.map((c) => c.message),
    matchFactors: match.factors,
  });
  const raw = await ai.structured({ instructions, input, name: 'naviq_match_explanation', schema: EXPLAIN_JSON_SCHEMA, maxOutputTokens: 700 });
  const parsed = z.object({ explanation: z.string().min(1).max(2000), nextSteps: z.array(z.string().max(300)).max(5) }).safeParse(raw);
  if (!parsed.success) throw invalid();
  return parsed.data;
}
