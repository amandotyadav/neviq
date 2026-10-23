import { checkEligibility, OVERALL, normalizeDegree } from '../eligibility/engine.js';
import { computeAvailability } from '../models/Opportunity.js';
import { calendarDaysUntil } from '../utils/dates.js';

/**
 * Explainable relevance ranking. Hard eligibility (deterministic engine) is
 * kept separate from relevance: a failed mandatory criterion always pushes a
 * listing below every eligible one, whatever its relevance.
 *
 * The score is a heuristic "match strength" (0–100), NOT a probability of
 * selection.
 */

const norm = (s) => String(s ?? '').toLowerCase().replace(/[^a-z0-9]+/g, '');

/** Interest keywords that map onto opportunity types. */
const TYPE_INTERESTS = {
  scholarship: ['scholarship', 'scholarships', 'financialaid', 'funding'],
  internship: ['internship', 'internships', 'industry'],
  research: ['research', 'science', 'academia'],
  fellowship: ['fellowship', 'fellowships', 'research'],
  competition: ['competition', 'competitions', 'hackathon', 'hackathons', 'ctf'],
  hackathon: ['hackathon', 'hackathons', 'competition'],
  program: ['opensource', 'mentorship', 'program'],
  job: ['job', 'jobs', 'placement', 'placements'],
};

const WEIGHTS = { skills: 35, interests: 25, education: 20, preferences: 10, timing: 10 };

export function scoreOpportunity(opp, profile, { now = new Date(), eligibility } = {}) {
  const p = profile ?? {};
  const factors = [];
  const elig = eligibility ?? checkEligibility(opp, p, { now });

  // Skills overlap.
  const oppSkills = [...(opp.requiredSkills ?? []), ...(opp.preferredSkills ?? [])];
  const mySkills = new Set((p.skills ?? []).map(norm));
  let skillsScore = 0;
  if (oppSkills.length) {
    const matched = oppSkills.filter((s) => mySkills.has(norm(s)));
    skillsScore = (matched.length / oppSkills.length) * WEIGHTS.skills;
    if (matched.length) factors.push({ factor: 'skills', positive: true, detail: `You list ${matched.join(', ')}, which this asks for.` });
    const missing = oppSkills.filter((s) => !mySkills.has(norm(s)));
    if (missing.length) factors.push({ factor: 'skills', positive: false, detail: `Not in your profile yet: ${missing.slice(0, 4).join(', ')}.` });
  } else {
    // No skill requirement published: neutral half credit.
    skillsScore = WEIGHTS.skills / 2;
  }

  // Interests vs tags and type.
  const interests = (p.interests ?? []).map(norm).filter(Boolean);
  const tags = (opp.tags ?? []).map(norm);
  const typeWords = TYPE_INTERESTS[opp.opportunityType] ?? [];
  const hitInterests = (p.interests ?? []).filter((i) => {
    const n = norm(i);
    return tags.some((t) => t.includes(n) || n.includes(t)) || typeWords.includes(n);
  });
  let interestScore = 0;
  if (interests.length) {
    interestScore = Math.min(1, hitInterests.length / Math.min(2, interests.length)) * WEIGHTS.interests;
    if (hitInterests.length) factors.push({ factor: 'interests', positive: true, detail: `Matches your interest in ${hitInterests.join(', ')}.` });
  }

  // Education compatibility (from deterministic results).
  const edu = elig.criteria.filter((c) => ['degree_in', 'year_in', 'branch_in', 'graduation_year_in'].includes(c.kind));
  let eduScore = WEIGHTS.education / 2;
  if (edu.length) {
    const met = edu.filter((c) => c.status === 'met');
    eduScore = (met.length / edu.length) * WEIGHTS.education;
    for (const c of met) factors.push({ factor: 'education', positive: true, detail: c.explanation });
    for (const c of edu.filter((x) => x.status === 'unmet')) factors.push({ factor: 'education', positive: false, detail: c.explanation });
  } else if (p.degree && (opp.eligibleDegrees ?? []).map(normalizeDegree).includes(normalizeDegree(p.degree))) {
    eduScore = WEIGHTS.education;
  }

  // Work mode / location preferences.
  let prefScore = WEIGHTS.preferences / 2;
  if ((p.workModes ?? []).length && ['remote', 'hybrid', 'onsite'].includes(opp.workMode)) {
    const ok = p.workModes.includes(opp.workMode);
    prefScore = ok ? WEIGHTS.preferences : 0;
    factors.push({ factor: 'work_mode', positive: ok, detail: ok ? `It is ${opp.workMode}, which you prefer.` : `It is ${opp.workMode}; you prefer ${p.workModes.join(' or ')}.` });
  } else if ((p.preferredLocations ?? []).length && (opp.location?.city || opp.location?.state)) {
    const loc = norm(`${opp.location.city ?? ''}${opp.location.state ?? ''}`);
    const ok = p.preferredLocations.some((l) => loc.includes(norm(l)));
    prefScore = ok ? WEIGHTS.preferences : WEIGHTS.preferences / 4;
    if (ok) factors.push({ factor: 'location', positive: true, detail: `Located in a place you prefer.` });
  } else if (opp.location?.isNationwide) {
    prefScore = WEIGHTS.preferences * 0.8;
  }

  // Timing: open with a verified deadline gets full credit.
  const availability = computeAvailability(opp, now);
  let timingScore = 0;
  if (availability === 'open') {
    timingScore = WEIGHTS.timing;
    if (opp.deadline) {
      const days = calendarDaysUntil(opp.deadline, now);
      factors.push({ factor: 'deadline', positive: true, detail: days <= 14 ? `Open now — closes in ${days} day${days === 1 ? '' : 's'}.` : 'Open now with a verified deadline.' });
    }
  } else if (availability === 'upcoming') timingScore = WEIGHTS.timing * 0.6;
  else if (availability === 'unknown') {
    timingScore = WEIGHTS.timing * 0.3;
    factors.push({ factor: 'deadline', positive: false, detail: 'Current application dates could not be verified.' });
  }

  // Audience-restricted criteria (gender, disability, existing awardee…) are
  // never inferred. Until the student confirms them, flag them first and do
  // not present the listing as a recommendation.
  const restricted = elig.criteria.filter((c) => c.mandatory && c.restrictsAudience && c.status !== 'met');
  for (const c of restricted) {
    factors.unshift({ factor: 'audience', positive: false, detail: `Only for: ${c.requirement.charAt(0).toLowerCase()}${c.requirement.slice(1)}. Check whether this applies to you.` });
  }

  // Uncertainty: each mandatory criterion Naviq cannot confirm lowers confidence.
  const unknownMandatory = elig.criteria.filter((c) => c.mandatory && c.status === 'unknown');
  const uncertaintyPenalty = Math.min(30, unknownMandatory.length * 4 + restricted.length * 10);
  if (unknownMandatory.length) {
    factors.push({ factor: 'uncertainty', positive: false, detail: `${unknownMandatory.length} required criteri${unknownMandatory.length === 1 ? 'on needs' : 'a need'} your confirmation.` });
  }

  const score = Math.max(0, Math.round(skillsScore + interestScore + eduScore + prefScore + timingScore - uncertaintyPenalty));

  return {
    score,
    scoreLabel: 'Heuristic match strength — not a probability of selection',
    eligibilityOverall: elig.overall,
    hardBlocked: elig.overall === OVERALL.LIKELY_INELIGIBLE,
    audienceRestricted: restricted.length > 0,
    // At least one published criterion was checked against the student's profile and met.
    // Without this, relevance rests on keywords alone, so it is not recommended.
    confirmedFit: elig.counts.met > 0,
    availability,
    factors,
  };
}

/** Sort: eligible before blocked; then by score; ties by nearest deadline. */
export function rankMatches(items) {
  return items.sort((a, b) => {
    if (a.match.hardBlocked !== b.match.hardBlocked) return a.match.hardBlocked ? 1 : -1;
    if (b.match.score !== a.match.score) return b.match.score - a.match.score;
    const da = a.opportunity.deadline ? new Date(a.opportunity.deadline).getTime() : Infinity;
    const db = b.opportunity.deadline ? new Date(b.opportunity.deadline).getTime() : Infinity;
    return da - db;
  });
}
