import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import { connectTestDb, disconnectTestDb, createOpportunity } from './helpers.js';
import { ingestScrapedRecords, retireMissing } from '../src/ingestion/importer.js';
import { runDailyRefresh } from '../src/ingestion/refresh.js';
import { nextRunAt } from '../src/ingestion/scheduler.js';
import { Opportunity } from '../src/models/Opportunity.js';
import { IngestRun } from '../src/models/IngestRun.js';

beforeAll(async () => { await connectTestDb('refresh'); });
afterAll(disconnectTestDb);
beforeEach(async () => { await Opportunity.deleteMany({}); await IngestRun.deleteMany({}); });

const scraped = (externalId, extra = {}) => ({
  externalId,
  title: `Scraped ${externalId}`,
  organization: 'Ministry of Fixtures',
  opportunityType: 'scholarship',
  sourceUrl: 'https://fixture.example.test/all',
  sourceType: 'government_portal',
  verificationStatus: 'verified',
  lastVerifiedAt: new Date().toISOString(),
  verifiedBy: 'naviq-ingest:nsp',
  declaredStatus: 'open',
  deadline: new Date(Date.now() + 20 * 86400000).toISOString(),
  award: null,
  stipend: null,
  eligibilityRules: [{ key: 'guidelines', kind: 'self_declared', label: 'Read the guidelines', mandatory: true }],
  status: 'published',
  ...extra,
});

describe('scraped record merge', () => {
  it('inserts new records, then refreshes them without duplicating', async () => {
    const first = await ingestScrapedRecords([scraped('nsp:a'), scraped('nsp:b')]);
    expect(first).toMatchObject({ inserted: 2, updated: 0 });
    const later = new Date(Date.now() + 40 * 86400000).toISOString();
    const second = await ingestScrapedRecords([scraped('nsp:a', { deadline: later }), scraped('nsp:b')]);
    expect(second).toMatchObject({ inserted: 0, updated: 2 });
    expect(await Opportunity.countDocuments()).toBe(2);
    expect((await Opportunity.findOne({ externalId: 'nsp:a' })).deadline.toISOString()).toBe(later);
  });

  it('never overwrites hand-verified rules or amounts, only dates and status', async () => {
    await createOpportunity({
      title: 'Curated', externalId: 'nsp:curated', verifiedBy: 'naviq-research',
      award: { amount: 50000, currency: 'INR', period: 'per_year' },
      eligibilityRules: [{ key: 'income', kind: 'max_family_income', label: 'Income ≤ 8L', mandatory: true, numberValue: 800000 }],
      deadline: new Date('2026-10-31'),
    });
    const newDeadline = new Date(Date.now() + 30 * 86400000).toISOString();
    const report = await ingestScrapedRecords([scraped('nsp:curated', { title: 'Scraped title', deadline: newDeadline, eligibilityRules: [{ key: 'x', kind: 'self_declared', label: 'x', mandatory: true }] })]);
    expect(report.datesRefreshed).toBe(1);
    const o = await Opportunity.findOne({ externalId: 'nsp:curated' });
    expect(o.title).toBe('Curated');
    expect(o.award.amount).toBe(50000);
    expect(o.eligibilityRules[0].key).toBe('income');
    expect(o.deadline.toISOString()).toBe(newDeadline);
    expect(o.datesRefreshedAt).toBeTruthy();
  });

  it('applies dates-only updates to existing records and ignores unknown ones', async () => {
    await createOpportunity({ title: 'SRFP', externalId: 'ias:srfp' });
    const d = new Date(Date.now() + 9 * 86400000).toISOString();
    const r = await ingestScrapedRecords([{ externalId: 'ias:srfp', datesOnly: true, deadline: d }, { externalId: 'ias:missing', datesOnly: true, deadline: d }]);
    expect(r).toMatchObject({ datesRefreshed: 1, skipped: 1 });
    expect((await Opportunity.findOne({ externalId: 'ias:srfp' })).deadline.toISOString()).toBe(d);
  });

  it('rejects invalid records with reasons instead of importing them', async () => {
    const r = await ingestScrapedRecords([scraped('nsp:bad', { sourceUrl: 'not-a-url' }), scraped('nsp:nometa', { verifiedBy: undefined })]);
    expect(r.inserted).toBe(0);
    expect(r.rejected).toHaveLength(2);
  });
});

describe('retiring vanished listings', () => {
  it('flags listings the source no longer shows', async () => {
    await ingestScrapedRecords([scraped('nsp:a'), scraped('nsp:b'), scraped('nsp:c')]);
    const out = await retireMissing({ okSources: ['nsp'], seen: new Set(['nsp:a', 'nsp:b']) });
    expect(out.retired).toBe(1);
    expect((await Opportunity.findOne({ externalId: 'nsp:c' })).verificationStatus).toBe('needs_review');
    expect((await Opportunity.findOne({ externalId: 'nsp:a' })).verificationStatus).toBe('verified');
  });

  it('retires nothing when the source returned under half of what we hold (layout change guard)', async () => {
    await ingestScrapedRecords([scraped('nsp:a'), scraped('nsp:b'), scraped('nsp:c'), scraped('nsp:d')]);
    const out = await retireMissing({ okSources: ['nsp'], seen: new Set(['nsp:a']) });
    expect(out).toMatchObject({ retired: 0, skippedSources: ['nsp'] });
  });
});

describe('daily refresh', () => {
  it('records a run, tolerates a failing source, and reports status', async () => {
    const scraper = async () => ({
      sources: [{ id: 'nsp', status: 'ok', count: 1, message: 'fine' }, { id: 'nicsi', status: 'error', count: 0, message: 'boom' }, { id: 'aicte_internships', status: 'skipped', count: 0, message: 'robots' }],
      records: [scraped('nsp:z')],
    });
    const run = await runDailyRefresh({ scraper, linkCheck: false, trigger: 'manual' });
    expect(run.status).toBe('partial');
    expect(run.inserted).toBe(1);
    const saved = await IngestRun.findOne();
    expect(saved.sources.map((s) => s.status)).toEqual(['ok', 'error', 'skipped']);
  });

  it('records a failed run when the scraper itself crashes, without throwing', async () => {
    const run = await runDailyRefresh({ scraper: async () => { throw new Error('python missing'); }, linkCheck: false });
    expect(run.status).toBe('failed');
    expect((await IngestRun.findOne()).error).toMatch(/python missing/);
  });
});

describe('scheduler timing', () => {
  it('picks the next 03:00 IST, today if still ahead, otherwise tomorrow', () => {
    expect(nextRunAt(3, new Date('2026-10-24T01:00:00+05:30')).toISOString()).toBe(new Date('2026-10-24T03:00:00+05:30').toISOString());
    expect(nextRunAt(3, new Date('2026-10-24T03:00:00+05:30')).toISOString()).toBe(new Date('2026-10-25T03:00:00+05:30').toISOString());
    expect(nextRunAt(3, new Date('2026-10-24T22:00:00+05:30')).toISOString()).toBe(new Date('2026-10-25T03:00:00+05:30').toISOString());
  });
});

describe('recommendations need a confirmed fit', () => {
  it('does not recommend listings where no criterion could be checked against the profile', async () => {
    const { checkEligibility } = await import('../src/eligibility/engine.js');
    const { scoreOpportunity } = await import('../src/matching/engine.js');
    const student = { degree: 'B.Tech', currentYear: 2, skills: ['Python'], interests: ['research'] };
    const onlyUnknown = { verificationStatus: 'verified', lastVerifiedAt: new Date(), declaredStatus: 'open', deadline: new Date(Date.now() + 5 * 86400000), tags: ['fellowship'], eligibilityRules: [{ key: 'guidelines', kind: 'self_declared', label: 'Read guidelines', mandatory: true }] };
    expect(scoreOpportunity(onlyUnknown, student, { eligibility: checkEligibility(onlyUnknown, student) }).confirmedFit).toBe(false);
    const withYear = { ...onlyUnknown, eligibleYears: [2] };
    expect(scoreOpportunity(withYear, student, { eligibility: checkEligibility(withYear, student) }).confirmedFit).toBe(true);
  });
});

describe('missing dates stay unknown', () => {
  it('stores a null deadline as null, not 1970, and keeps the listing open to students', async () => {
    const r = await ingestScrapedRecords([scraped('isro:rolling', { deadline: null, declaredStatus: 'unknown', opportunityType: 'internship' })]);
    expect(r.inserted).toBe(1);
    const o = await Opportunity.findOne({ externalId: 'isro:rolling' });
    expect(o.deadline).toBeNull();
    const { computeAvailability } = await import('../src/models/Opportunity.js');
    expect(computeAvailability(o)).toBe('unknown');
  });
});
