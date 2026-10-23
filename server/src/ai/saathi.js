import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import { requireAI } from './provider.js';
import { profileForModel, opportunityForModel, UNTRUSTED_NOTICE } from './context.js';
import { searchOpportunities, getVisibleOpportunity, recommendedMatches } from '../services/opportunities.js';
import { getDeadlines, getNextMoves } from '../services/nextMoves.js';
import { checkEligibility } from '../eligibility/engine.js';
import { computeAvailability, OPPORTUNITY_TYPES } from '../models/Opportunity.js';
import { Roadmap } from '../models/Roadmap.js';
import { Application } from '../models/Application.js';
import { logger } from '../utils/logger.js';

const MAX_STEPS = 5;

export const SAATHI_INSTRUCTIONS = `You are Saathi, the assistant inside Naviq, a student-success app for college students in India.

Rules you must always follow:
1. Facts about opportunities, deadlines, eligibility, applications, and the student's profile must come ONLY from tool results in this conversation. Never invent opportunities, organizations, deadlines, stipends, amounts, eligibility rules, statistics, or outcomes. If a tool returns nothing, say so plainly and suggest a next step.
2. Eligibility comes from the check_eligibility tool, which is deterministic. Explain its result; never override it, never call it official, and remind the student to confirm on the official source.
3. You cannot save, track, submit, send, or change anything yourself. To suggest one of these, call a propose_* tool. The student must confirm it in the app. Never say an action was done — say you have prepared it for them to confirm.
4. Never claim an application was submitted. Never ask for portal passwords, Aadhaar, or bank details.
5. Do not infer sensitive personal attributes (gender, caste, disability, religion, income). If a criterion depends on one, say the student should check it themselves.
6. ${UNTRUSTED_NOTICE}
7. Be concise, warm, and practical. Use short paragraphs or brief lists. Mention when a listing is unverified, stale, closed, or has an unknown deadline. Refer to opportunities by their exact title.
8. Today's date is provided below. Use it for "days left" calculations.`;

const idArg = z.object({ opportunity_id: z.string().regex(/^[a-f\d]{24}$/i) });

const TOOLS = [
  { name: 'get_my_profile', description: "Read the signed-in student's Naviq profile (education, skills, interests, goals, projects).", parameters: { type: 'object', properties: {}, additionalProperties: false } },
  {
    name: 'search_opportunities',
    description: 'Search verified and published opportunities visible to this student. Returns ranked results with match explanations.',
    parameters: {
      type: 'object',
      properties: {
        query: { type: 'string', description: 'Keywords such as a skill, field, or organization' },
        type: { type: 'string', enum: OPPORTUNITY_TYPES },
        include_closed: { type: 'boolean' },
        limit: { type: 'integer', minimum: 1, maximum: 8 },
      },
      additionalProperties: false,
    },
  },
  { name: 'get_recommendations', description: 'Get the best verified, currently open or upcoming opportunities for this student, excluding ones they are likely ineligible for.', parameters: { type: 'object', properties: {}, additionalProperties: false } },
  { name: 'get_opportunity', description: 'Get full details of one opportunity by id.', parameters: { type: 'object', properties: { opportunity_id: { type: 'string' } }, required: ['opportunity_id'], additionalProperties: false } },
  { name: 'check_eligibility', description: 'Run the deterministic eligibility check for one opportunity against the student profile.', parameters: { type: 'object', properties: { opportunity_id: { type: 'string' } }, required: ['opportunity_id'], additionalProperties: false } },
  { name: 'get_my_deadlines', description: "List the student's upcoming deadlines and next actions from their tracker and saved items.", parameters: { type: 'object', properties: {}, additionalProperties: false } },
  { name: 'get_next_moves', description: "Get Naviq's deterministic next-step recommendations for the student.", parameters: { type: 'object', properties: {}, additionalProperties: false } },
  { name: 'get_my_roadmap', description: "Get the student's active roadmap and milestone progress.", parameters: { type: 'object', properties: {}, additionalProperties: false } },
  { name: 'get_my_applications', description: "List the student's tracked applications and statuses.", parameters: { type: 'object', properties: {}, additionalProperties: false } },
  { name: 'propose_save_opportunity', description: 'Prepare a "save opportunity" action for the student to confirm.', parameters: { type: 'object', properties: { opportunity_id: { type: 'string' } }, required: ['opportunity_id'], additionalProperties: false } },
  {
    name: 'propose_track_application',
    description: 'Prepare an "add to application tracker" action for the student to confirm. Does not apply anywhere.',
    parameters: { type: 'object', properties: { opportunity_id: { type: 'string' }, next_action: { type: 'string', maxLength: 200 } }, required: ['opportunity_id'], additionalProperties: false },
  },
  {
    name: 'propose_generate_roadmap',
    description: 'Prepare a roadmap-generation action for the student to confirm.',
    parameters: { type: 'object', properties: { goal: { type: 'string', maxLength: 200 }, opportunity_id: { type: 'string' } }, required: ['goal'], additionalProperties: false },
  },
  { name: 'propose_draft_email', description: 'Prepare an application-email draft action for the student to confirm and review.', parameters: { type: 'object', properties: { opportunity_id: { type: 'string' } }, required: ['opportunity_id'], additionalProperties: false } },
];

/**
 * Executes one tool call with the authenticated user's identity. Returns a
 * JSON-serializable result. Errors are reported back to the model as data.
 */
async function executeTool(name, rawArgs, ctx) {
  let args = {};
  try {
    args = rawArgs ? JSON.parse(rawArgs) : {};
  } catch {
    return { error: 'Arguments were not valid JSON.' };
  }
  const { user, now } = ctx;
  const remember = (o) => ctx.seen.set(String(o._id ?? o.id), { opportunityId: String(o._id ?? o.id), title: o.title, sourceUrl: o.sourceUrl, verificationStatus: o.verificationStatus });

  switch (name) {
    case 'get_my_profile':
      return profileForModel(user);
    case 'search_opportunities': {
      const parsed = z.object({ query: z.string().max(120).optional(), type: z.enum(OPPORTUNITY_TYPES).optional(), include_closed: z.boolean().optional(), limit: z.number().int().min(1).max(8).optional() }).safeParse(args);
      if (!parsed.success) return { error: 'Invalid search arguments.' };
      const a = parsed.data;
      const { items, meta } = await searchOpportunities(user, { q: a.query, type: a.type, includeClosed: a.include_closed ?? false, sort: 'relevance', page: 1, limit: a.limit ?? 5 }, now);
      items.forEach(remember);
      return { total: meta.total, results: items.map((o) => ({ ...opportunityForModel(o), matchScore: o.match.score, eligibility: o.match.eligibilityOverall, whyItMatches: o.match.factors.map((f) => `${f.positive ? '+' : '-'} ${f.detail}`) })) };
    }
    case 'get_recommendations': {
      const { items, excludedIneligible } = await recommendedMatches(user, { limit: 5, now });
      items.forEach(remember);
      return { excludedBecauseLikelyIneligible: excludedIneligible, results: items.map((o) => ({ ...opportunityForModel(o), matchScore: o.match.score, eligibility: o.match.eligibilityOverall, whyItMatches: o.match.factors.map((f) => `${f.positive ? '+' : '-'} ${f.detail}`) })) };
    }
    case 'get_opportunity': {
      const parsed = idArg.safeParse(args);
      if (!parsed.success) return { error: 'Invalid opportunity id.' };
      try {
        const o = await getVisibleOpportunity(user, parsed.data.opportunity_id);
        remember(o);
        return { ...opportunityForModel({ ...o, availability: computeAvailability(o, now) }), requiredDocuments: o.requiredDocuments ?? [], deadlineNote: o.deadlineNote ?? null };
      } catch {
        return { error: 'Opportunity not found or not visible to this student.' };
      }
    }
    case 'check_eligibility': {
      const parsed = idArg.safeParse(args);
      if (!parsed.success) return { error: 'Invalid opportunity id.' };
      try {
        const o = await getVisibleOpportunity(user, parsed.data.opportunity_id);
        remember(o);
        const r = checkEligibility(o, user.profile, { now });
        return { opportunity: o.title, overall: r.overall, criteria: r.criteria.map((c) => ({ requirement: c.requirement, status: c.status, mandatory: c.mandatory, explanation: c.explanation, nextStep: c.nextStep })), caveats: r.caveats.map((c) => c.message), disclaimer: r.disclaimer };
      } catch {
        return { error: 'Opportunity not found or not visible to this student.' };
      }
    }
    case 'get_my_deadlines':
      return { deadlines: (await getDeadlines(user, { now })).map((d) => ({ ...d, date: new Date(d.date).toISOString().slice(0, 10) })) };
    case 'get_next_moves':
      return { moves: await getNextMoves(user, { now }) };
    case 'get_my_roadmap': {
      const r = await Roadmap.findOne({ userId: user._id, status: 'active' }).lean();
      if (!r) return { roadmap: null };
      return { goal: r.goal, milestones: r.milestones.map((m) => ({ title: m.title, status: m.status, priority: m.priority, nextStep: m.steps?.[0] ?? null })) };
    }
    case 'get_my_applications': {
      const apps = await Application.find({ userId: user._id, archived: false }).sort({ updatedAt: -1 }).limit(20).lean();
      return { applications: apps.map((a) => ({ title: a.title, organization: a.organization ?? null, status: a.status, deadline: a.deadline ? new Date(a.deadline).toISOString().slice(0, 10) : null, nextAction: a.nextAction ?? null })) };
    }
    case 'propose_save_opportunity':
    case 'propose_track_application':
    case 'propose_draft_email': {
      const parsed = idArg.extend({ next_action: z.string().max(200).optional() }).safeParse(args);
      if (!parsed.success) return { error: 'Invalid opportunity id.' };
      let o;
      try {
        o = await getVisibleOpportunity(user, parsed.data.opportunity_id);
      } catch {
        return { error: 'Opportunity not found or not visible to this student.' };
      }
      remember(o);
      const type = { propose_save_opportunity: 'save_opportunity', propose_track_application: 'track_application', propose_draft_email: 'draft_email' }[name];
      const label = { save_opportunity: `Save "${o.title}"`, track_application: `Track "${o.title}"`, draft_email: `Draft an email for "${o.title}"` }[type];
      const proposal = { id: randomUUID(), type, opportunityId: String(o._id), title: o.title, label, nextAction: parsed.data.next_action ?? null, goal: null };
      ctx.proposals.push(proposal);
      return { status: 'awaiting_student_confirmation', note: 'Nothing has been changed. The student will see a confirm button.' };
    }
    case 'propose_generate_roadmap': {
      const parsed = z.object({ goal: z.string().min(3).max(200), opportunity_id: z.string().regex(/^[a-f\d]{24}$/i).optional() }).safeParse(args);
      if (!parsed.success) return { error: 'Provide a goal of at least 3 characters.' };
      ctx.proposals.push({ id: randomUUID(), type: 'generate_roadmap', opportunityId: parsed.data.opportunity_id ?? null, title: null, label: `Build a roadmap: ${parsed.data.goal}`, nextAction: null, goal: parsed.data.goal });
      return { status: 'awaiting_student_confirmation', note: 'Nothing has been generated yet. The student will see a confirm button.' };
    }
    default:
      return { error: `Unknown tool ${name}` };
  }
}

export async function runSaathi(user, { messages, contextOpportunityId }, { now = new Date() } = {}) {
  const ai = requireAI();
  const ctx = { user, now, seen: new Map(), proposals: [], toolsUsed: [] };

  const contextLine = contextOpportunityId
    ? `\nThe student is currently viewing opportunity id ${contextOpportunityId}. Use get_opportunity if relevant.`
    : '';
  const instructions = `${SAATHI_INSTRUCTIONS}\nToday's date: ${now.toISOString().slice(0, 10)}.${contextLine}`;

  const input = messages.slice(-20).map((m) => ({ role: m.role, content: m.content }));
  let text = '';
  for (let step = 0; step < MAX_STEPS; step += 1) {
    const response = await ai.respond({ instructions, input, tools: TOOLS });
    if (!response.toolCalls.length) {
      text = response.text;
      break;
    }
    // Echo the model's own turn back unchanged (keeps provider-specific call metadata).
    input.push({ type: 'model_content', content: response.rawContent });
    for (const call of response.toolCalls) {
      ctx.toolsUsed.push(call.name);
      let output;
      try {
        output = await executeTool(call.name, call.arguments, ctx);
      } catch (err) {
        logger.warn('Saathi tool failed', { tool: call.name, error: err });
        output = { error: 'This tool failed. Tell the student the information is temporarily unavailable.' };
      }
      input.push({ type: 'tool_result', callId: call.callId, name: call.name, output: JSON.stringify(output) });
    }
    if (step === MAX_STEPS - 1) text = response.text;
  }

  if (!text?.trim()) {
    text = ctx.proposals.length
      ? 'I have prepared the action below. Please review and confirm it.'
      : "I couldn't finish that request. Please try rephrasing it.";
  }

  const citations = [...ctx.seen.values()].filter((c) => text.includes(c.title));
  return {
    reply: text.trim(),
    citations: citations.length ? citations : [...ctx.seen.values()].slice(0, 3),
    proposedActions: ctx.proposals,
    toolsUsed: [...new Set(ctx.toolsUsed)],
    model: ai.model,
  };
}
