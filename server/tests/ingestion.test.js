import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { readFile } from 'node:fs/promises';
import { connectTestDb, disconnectTestDb, createOpportunity } from './helpers.js';
import { importOpportunities } from '../src/ingestion/importer.js';
import { checkSources } from '../src/ingestion/sourceChecker.js';
import { Opportunity } from '../src/models/Opportunity.js';

beforeAll(async () => { await connectTestDb('ingest'); });
afterAll(disconnectTestDb);

describe('verified data import', () => {
  it('accepts every record in the shipped verified dataset and dedupes on re-import', async () => {
    const { records } = JSON.parse(await readFile(new URL('../data/verified-opportunities.json', import.meta.url), 'utf8'));
    const first = await importOpportunities(records);
    expect(first.rejected).toEqual([]);
    expect(first.inserted).toBe(records.length);
    const second = await importOpportunities(records);
    expect(second.inserted).toBe(0);
    expect(second.updated).toBe(records.length);
    expect(await Opportunity.countDocuments()).toBe(records.length);
    // Every shipped record has an official https source and verification metadata.
    for (const o of await Opportunity.find().lean()) {
      expect(o.sourceUrl).toMatch(/^https:\/\//);
      expect(o.lastVerifiedAt).toBeTruthy();
      expect(o.verifiedBy).toBeTruthy();
    }
  });

  it('rejects verified records without verification metadata', async () => {
    const report = await importOpportunities([{ title: 'No proof', organization: 'Org', opportunityType: 'internship', sourceUrl: 'https://x.example.test', sourceType: 'official_org_site', verificationStatus: 'verified' }]);
    expect(report.rejected).toHaveLength(1);
  });

  it('marks listings whose source disappeared as needs_review', async () => {
    const gone = await createOpportunity({ title: 'Gone listing', sourceUrl: 'https://gone.example.test/page' });
    const fine = await createOpportunity({ title: 'Fine listing', sourceUrl: 'https://fine.example.test/page' });
    const fetchImpl = async (url) => ({ status: url.includes('gone') ? 404 : 200 });
    await checkSources({ fetchImpl });
    expect((await Opportunity.findById(gone._id)).verificationStatus).toBe('needs_review');
    expect((await Opportunity.findById(fine._id)).verificationStatus).toBe('verified');
  });
});
