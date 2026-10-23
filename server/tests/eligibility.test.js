import { describe, it, expect } from 'vitest';
import { checkEligibility, OVERALL } from '../src/eligibility/engine.js';
import { scoreOpportunity, rankMatches } from '../src/matching/engine.js';

const now = new Date('2026-10-23T12:00:00+05:30');
const base = {
  _id: 'x',
  verificationStatus: 'verified',
  lastVerifiedAt: now,
  declaredStatus: 'open',
  deadline: new Date('2026-11-30T23:59:59+05:30'),
  eligibilityRules: [],
};
const student = { degree: 'B.Tech', branch: 'Computer Science and Engineering', currentYear: 2, skills: ['Python', 'Linux'], interests: ['cybersecurity', 'research'] };

describe('eligibility engine', () => {
  it('reports all criteria met when every mandatory rule passes', () => {
    const r = checkEligibility({ ...base, eligibleDegrees: ['B.E.', 'B.Tech'], eligibleYears: [2, 3] }, student, { now });
    expect(r.overall).toBe(OVERALL.ALL_MET);
    expect(r.criteria.every((c) => c.status === 'met')).toBe(true);
  });

  it('treats degree aliases consistently (BTech == B.Tech) and branch aliases (CSE)', () => {
    const r = checkEligibility({ ...base, eligibleDegrees: ['BTech'], eligibleBranches: ['CSE'] }, student, { now });
    expect(r.overall).toBe(OVERALL.ALL_MET);
  });

  it('flags likely ineligible when a mandatory criterion is unmet', () => {
    const r = checkEligibility({ ...base, eligibleYears: [3, 4] }, student, { now });
    expect(r.overall).toBe(OVERALL.LIKELY_INELIGIBLE);
    const year = r.criteria.find((c) => c.kind === 'year_in');
    expect(year.status).toBe('unmet');
    expect(year.nextStep).toMatch(/future cycle/);
  });

  it('reports missing information when profile data is absent', () => {
    const r = checkEligibility({ ...base, minimumCGPA: 7 }, { ...student, cgpa: undefined }, { now });
    expect(r.overall).toBe(OVERALL.MISSING_INFO);
    expect(r.criteria[0].status).toBe('unknown');
  });

  it('keeps self-declared criteria unknown unless the student confirms them', () => {
    const opp = { ...base, eligibilityRules: [{ key: 'girl_student', kind: 'self_declared', label: 'Girl student', mandatory: true }] };
    expect(checkEligibility(opp, student, { now }).overall).toBe(OVERALL.MISSING_INFO);
    expect(checkEligibility(opp, student, { now, declarations: { girl_student: true } }).overall).toBe(OVERALL.ALL_MET);
    expect(checkEligibility(opp, student, { now, declarations: { girl_student: false } }).overall).toBe(OVERALL.LIKELY_INELIGIBLE);
  });

  it('checks income only when the student chose to share it', () => {
    const opp = { ...base, eligibilityRules: [{ key: 'income', kind: 'max_family_income', label: 'Income ≤ 8L', mandatory: true, numberValue: 800000 }] };
    expect(checkEligibility(opp, student, { now }).criteria[0].status).toBe('unknown');
    expect(checkEligibility(opp, { ...student, annualFamilyIncomeINR: 500000 }, { now }).criteria[0].status).toBe('met');
    expect(checkEligibility(opp, { ...student, annualFamilyIncomeINR: 900000 }, { now }).criteria[0].status).toBe('unmet');
  });

  it('cannot assess when the source has no structured criteria', () => {
    expect(checkEligibility(base, student, { now }).overall).toBe(OVERALL.INSUFFICIENT_SOURCE);
  });

  it('cannot assess unverified listings even if rules pass', () => {
    const r = checkEligibility({ ...base, verificationStatus: 'unverified', eligibleYears: [2] }, student, { now });
    expect(r.overall).toBe(OVERALL.INSUFFICIENT_SOURCE);
    expect(r.caveats.map((c) => c.code)).toContain('source_unverified');
  });

  it('adds caveats for closed, stale, and unknown-deadline listings', () => {
    const closed = checkEligibility({ ...base, deadline: new Date('2026-10-01'), eligibleYears: [2] }, student, { now });
    expect(closed.caveats.map((c) => c.code)).toContain('closed');
    const stale = checkEligibility({ ...base, lastVerifiedAt: new Date('2026-08-01'), eligibleYears: [2] }, student, { now });
    expect(stale.caveats.map((c) => c.code)).toContain('source_stale');
    const unknown = checkEligibility({ ...base, deadline: null, eligibleYears: [2] }, student, { now });
    expect(unknown.caveats.map((c) => c.code)).toContain('deadline_unknown');
  });

  it('always includes a non-official disclaimer', () => {
    expect(checkEligibility(base, student, { now }).disclaimer).toMatch(/not an official eligibility decision/i);
  });
});

describe('calendar day counting', async () => {
  const { calendarDaysUntil } = await import('../src/utils/dates.js');
  it('counts calendar days in IST, not rounded milliseconds', () => {
    const at = new Date('2026-10-23T20:00:00+05:30');
    expect(calendarDaysUntil(new Date('2026-10-31T23:59:59+05:30'), at)).toBe(8);
    expect(calendarDaysUntil(new Date('2026-10-23T23:59:00+05:30'), at)).toBe(0);
  });
});

describe('matching engine', () => {
  it('flags audience-restricted criteria and never treats them as a fit until confirmed', () => {
    const opp = { ...base, eligibleYears: [2], eligibilityRules: [{ key: 'girl_student', kind: 'self_declared', label: 'Applicant is a girl student', mandatory: true, restrictsAudience: true }] };
    const m = scoreOpportunity(opp, student, { now });
    expect(m.audienceRestricted).toBe(true);
    expect(m.factors[0]).toMatchObject({ factor: 'audience', positive: false });
    const confirmed = scoreOpportunity(opp, student, { now, eligibility: checkEligibility(opp, student, { now, declarations: { girl_student: true } }) });
    expect(confirmed.audienceRestricted).toBe(false);
  });

  it('explains positive factors using real profile facts', () => {
    const m = scoreOpportunity({ ...base, requiredSkills: ['Python'], tags: ['cybersecurity'], eligibleYears: [2] }, student, { now });
    const details = m.factors.filter((f) => f.positive).map((f) => f.detail).join(' ');
    expect(details).toMatch(/Python/);
    expect(details).toMatch(/cybersecurity/);
    expect(m.scoreLabel).toMatch(/not a probability/i);
  });

  it('never ranks a hard-blocked listing above an eligible one, whatever the score', () => {
    const strong = { ...base, _id: 'a', requiredSkills: ['Python', 'Linux'], tags: ['cybersecurity', 'research'], eligibleYears: [4] };
    const weak = { ...base, _id: 'b', requiredSkills: ['Rust'], eligibleYears: [2] };
    const rows = [strong, weak].map((o) => ({ opportunity: o, match: scoreOpportunity(o, student, { now }) }));
    expect(rows[0].match.score).toBeGreaterThan(rows[1].match.score);
    const ranked = rankMatches(rows);
    expect(ranked[0].opportunity._id).toBe('b');
    expect(ranked[1].match.hardBlocked).toBe(true);
  });
});
