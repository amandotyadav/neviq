import { computeAvailability, isStale } from '../models/Opportunity.js';

/**
 * Deterministic eligibility engine.
 *
 * Each criterion is evaluated against the student's own profile and returns
 * met / unmet / unknown with an explanation and next step. The LLM never
 * participates here; AI features may only *explain* these results.
 *
 * `declarations` are per-check, student-provided answers for criteria Naviq
 * cannot verify (e.g. "I hold a valid income certificate"). They are used
 * only for this evaluation and are never stored.
 */

const norm = (s) => String(s ?? '').toLowerCase().replace(/[^a-z0-9]+/g, '');

const DEGREE_ALIASES = {
  btech: 'btech', bachelorOfTechnology: 'btech', bacheloroftechnology: 'btech',
  be: 'be', bachelorofengineering: 'be',
  bsc: 'bsc', bachelorofscience: 'bsc', bs: 'bs',
  bca: 'bca', bcom: 'bcom', ba: 'ba', bba: 'bba', barch: 'barch', bpharm: 'bpharm', mbbs: 'mbbs',
  mtech: 'mtech', me: 'me', msc: 'msc', ms: 'ms', mca: 'mca', mba: 'mba', ma: 'ma',
  diploma: 'diploma', polytechnicdiploma: 'diploma', integrated: 'integrated', dualdegree: 'integrated',
  phd: 'phd',
};
export const normalizeDegree = (d) => DEGREE_ALIASES[norm(d)] ?? norm(d);

const BRANCH_ALIASES = {
  cse: 'cse', computerscience: 'cse', computerscienceandengineering: 'cse', computerscienceengineering: 'cse', cs: 'cse',
  it: 'it', informationtechnology: 'it',
  ece: 'ece', electronicsandcommunication: 'ece', electronicsandcommunicationengineering: 'ece',
  ee: 'ee', eee: 'ee', electricalengineering: 'ee', electricalandelectronicsengineering: 'ee',
  me: 'mech', mech: 'mech', mechanical: 'mech', mechanicalengineering: 'mech',
  ce: 'civil', civil: 'civil', civilengineering: 'civil',
  aiml: 'aiml', artificialintelligenceandmachinelearning: 'aiml', csaiml: 'aiml',
  ds: 'datascience', datascience: 'datascience', csds: 'datascience',
  cybersecurity: 'cybersecurity', cscybersecurity: 'cybersecurity',
};
export const normalizeBranch = (b) => BRANCH_ALIASES[norm(b)] ?? norm(b);

const fmtINR = (n) => `₹${Number(n).toLocaleString('en-IN')}`;
const list = (arr) => arr.join(', ');

function result(rule, status, studentValue, explanation, nextStep) {
  return {
    key: rule.key,
    kind: rule.kind,
    requirement: rule.label,
    mandatory: rule.mandatory !== false,
    studentValue: studentValue ?? null,
    status,
    explanation,
    nextStep: nextStep ?? null,
    sourceExcerpt: rule.sourceExcerpt ?? null,
    restrictsAudience: Boolean(rule.restrictsAudience),
  };
}

function evaluateRule(rule, profile, declarations) {
  const p = profile ?? {};
  const values = rule.values ?? [];
  switch (rule.kind) {
    case 'degree_in': {
      if (!p.degree) return result(rule, 'unknown', null, 'Your degree is not in your profile.', 'Add your degree in Profile.');
      const ok = values.map(normalizeDegree).includes(normalizeDegree(p.degree));
      return ok
        ? result(rule, 'met', p.degree, `Your degree (${p.degree}) is listed: ${list(values)}.`)
        : result(rule, 'unmet', p.degree, `This requires ${list(values)}; your profile says ${p.degree}.`,
          'If your profile is wrong, update it. Otherwise look for similar opportunities open to your degree.');
    }
    case 'branch_in': {
      if (!p.branch) return result(rule, 'unknown', null, 'Your branch is not in your profile.', 'Add your branch in Profile.');
      const ok = values.map(normalizeBranch).includes(normalizeBranch(p.branch));
      return ok
        ? result(rule, 'met', p.branch, `Your branch (${p.branch}) is eligible.`)
        : result(rule, 'unmet', p.branch, `Eligible branches: ${list(values)}. Yours: ${p.branch}.`,
          'Check the official source in case related branches are accepted.');
    }
    case 'year_in': {
      if (!p.currentYear) return result(rule, 'unknown', null, 'Your current year of study is not in your profile.', 'Add your current year in Profile.');
      const years = values.map(Number);
      const ok = years.includes(Number(p.currentYear));
      return ok
        ? result(rule, 'met', `Year ${p.currentYear}`, `You are in year ${p.currentYear}; eligible years: ${list(values)}.`)
        : result(rule, 'unmet', `Year ${p.currentYear}`, `Only year ${list(values)} students are eligible; you are in year ${p.currentYear}.`,
          years.some((y) => y > p.currentYear) ? 'You may qualify in a future cycle — save it and check again next year.' : null);
    }
    case 'graduation_year_in': {
      if (!p.graduationYear) return result(rule, 'unknown', null, 'Your graduation year is not in your profile.', 'Add your graduation year in Profile.');
      const ok = values.map(Number).includes(Number(p.graduationYear));
      return ok
        ? result(rule, 'met', String(p.graduationYear), `Graduating in ${p.graduationYear} is eligible.`)
        : result(rule, 'unmet', String(p.graduationYear), `Eligible graduation years: ${list(values)}.`);
    }
    case 'min_cgpa': {
      if (p.cgpa == null) return result(rule, 'unknown', null, `Requires a CGPA of at least ${rule.numberValue}. Your CGPA is not in your profile.`, 'Add your CGPA in Profile (optional).');
      const ok = Number(p.cgpa) >= Number(rule.numberValue);
      return ok
        ? result(rule, 'met', `CGPA ${p.cgpa}`, `Your CGPA ${p.cgpa} meets the minimum of ${rule.numberValue}.`)
        : result(rule, 'unmet', `CGPA ${p.cgpa}`, `Requires at least ${rule.numberValue}; yours is ${p.cgpa}.`,
          'Confirm the CGPA scale used by the source; scales differ between institutions.');
    }
    case 'max_family_income': {
      if (p.annualFamilyIncomeINR == null) {
        return result(rule, 'unknown', null,
          `Annual family income must not exceed ${fmtINR(rule.numberValue)}. You have not shared income in Naviq (optional).`,
          'Check this against your income certificate, or add it privately in Profile to have Naviq check it.');
      }
      const ok = Number(p.annualFamilyIncomeINR) <= Number(rule.numberValue);
      return ok
        ? result(rule, 'met', 'Within limit', `Your stated family income is within the ${fmtINR(rule.numberValue)} limit.`)
        : result(rule, 'unmet', 'Above limit', `Your stated family income is above the ${fmtINR(rule.numberValue)} limit.`,
          'If your stated income is out of date, update it in Profile.');
    }
    case 'home_state_in': {
      if (!p.homeState) return result(rule, 'unknown', null, `Restricted to: ${list(values)}. Your home state is not in your profile.`, 'Add your home state in Profile (optional).');
      const ok = values.map(norm).includes(norm(p.homeState));
      return ok
        ? result(rule, 'met', p.homeState, `${p.homeState} is an eligible state.`)
        : result(rule, 'unmet', p.homeState, `Restricted to: ${list(values)}.`);
    }
    case 'skills_all':
    case 'skills_any': {
      const mine = new Set((p.skills ?? []).map(norm));
      if (mine.size === 0) return result(rule, 'unknown', null, 'You have not added skills yet.', 'Add your skills in Profile.');
      const have = values.filter((v) => mine.has(norm(v)));
      const missing = values.filter((v) => !mine.has(norm(v)));
      const ok = rule.kind === 'skills_all' ? missing.length === 0 : have.length > 0;
      return ok
        ? result(rule, 'met', list(have), `You list ${list(have)}.`)
        : result(rule, 'unmet', have.length ? list(have) : 'None listed',
          `Missing: ${list(missing)}.`, `Build and evidence ${list(missing.slice(0, 3))} — try adding them to your roadmap.`);
    }
    case 'self_declared': {
      const answer = declarations?.[rule.key];
      if (answer === true) return result(rule, 'met', null, 'You confirmed this criterion. Naviq cannot verify it for you.');
      if (answer === false) return result(rule, 'unmet', null, 'You indicated you do not meet this criterion.');
      return result(rule, 'unknown', null, rule.note ?? 'Naviq cannot verify this from your profile.',
        'Read this criterion on the official source and confirm it yourself.');
    }
    default:
      return result(rule, 'unknown', null, 'This criterion type is not supported for automatic checking.');
  }
}

/** Rules derived from top-level structured fields when no explicit rule covers them. */
function derivedRules(opp) {
  const explicit = new Set((opp.eligibilityRules ?? []).map((r) => r.kind));
  const rules = [];
  if (opp.eligibleDegrees?.length && !explicit.has('degree_in')) {
    rules.push({ key: 'degree', kind: 'degree_in', label: `Degree: ${opp.eligibleDegrees.join(', ')}`, mandatory: true, values: opp.eligibleDegrees });
  }
  if (opp.eligibleYears?.length && !explicit.has('year_in')) {
    rules.push({ key: 'year', kind: 'year_in', label: `Year of study: ${opp.eligibleYears.join(', ')}`, mandatory: true, values: opp.eligibleYears.map(String) });
  }
  if (opp.eligibleBranches?.length && !explicit.has('branch_in')) {
    rules.push({ key: 'branch', kind: 'branch_in', label: `Branch: ${opp.eligibleBranches.join(', ')}`, mandatory: true, values: opp.eligibleBranches });
  }
  if (opp.minimumCGPA != null && !explicit.has('min_cgpa')) {
    rules.push({ key: 'cgpa', kind: 'min_cgpa', label: `Minimum CGPA ${opp.minimumCGPA}`, mandatory: true, numberValue: opp.minimumCGPA });
  }
  if (opp.requiredSkills?.length && !explicit.has('skills_all') && !explicit.has('skills_any')) {
    rules.push({ key: 'skills', kind: 'skills_all', label: `Skills: ${opp.requiredSkills.join(', ')}`, mandatory: false, values: opp.requiredSkills });
  }
  return rules;
}

export const OVERALL = {
  ALL_MET: 'all_criteria_met',
  MISSING_INFO: 'missing_information',
  LIKELY_INELIGIBLE: 'likely_ineligible',
  INSUFFICIENT_SOURCE: 'insufficient_source_info',
};

export function checkEligibility(opportunity, profile, { declarations = {}, now = new Date() } = {}) {
  const rules = [...(opportunity.eligibilityRules ?? []), ...derivedRules(opportunity)];
  const criteria = rules.map((r) => evaluateRule(r, profile, declarations));

  const mandatory = criteria.filter((c) => c.mandatory);
  const counts = {
    met: criteria.filter((c) => c.status === 'met').length,
    unmet: criteria.filter((c) => c.status === 'unmet').length,
    unknown: criteria.filter((c) => c.status === 'unknown').length,
  };

  let overall;
  if (criteria.length === 0 || opportunity.verificationStatus === 'unverified') {
    overall = OVERALL.INSUFFICIENT_SOURCE;
  } else if (mandatory.some((c) => c.status === 'unmet')) {
    overall = OVERALL.LIKELY_INELIGIBLE;
  } else if (mandatory.some((c) => c.status === 'unknown')) {
    overall = OVERALL.MISSING_INFO;
  } else {
    overall = OVERALL.ALL_MET;
  }

  const caveats = [];
  const availability = computeAvailability(opportunity, now);
  if (availability === 'closed') caveats.push({ code: 'closed', message: 'Applications appear to be closed for this cycle.' });
  if (!opportunity.deadline) caveats.push({ code: 'deadline_unknown', message: 'The official source does not state a deadline Naviq could verify.' });
  if (opportunity.verificationStatus !== 'verified') caveats.push({ code: 'source_unverified', message: 'This listing has not been verified against its official source yet.' });
  else if (isStale(opportunity, now)) caveats.push({ code: 'source_stale', message: 'This listing was last verified over 30 days ago. Details may have changed.' });

  return {
    opportunityId: String(opportunity._id ?? opportunity.id ?? ''),
    overall,
    counts,
    criteria,
    caveats,
    availability,
    disclaimer: 'This is a guidance check based on your Naviq profile and the published criteria. It is not an official eligibility decision. Always confirm on the official source.',
    checkedAt: now.toISOString(),
  };
}
