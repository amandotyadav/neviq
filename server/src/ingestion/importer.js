import { z } from 'zod';
import { Opportunity, buildDedupeKey } from '../models/Opportunity.js';
import { College, normalizeCollegeName } from '../models/College.js';
import { Resource } from '../models/Resource.js';
import { adminOpportunityCreateSchema } from '../validators/schemas.js';

/**
 * Verified-record import. A record is accepted only if it validates and —
 * when marked verified — carries who verified it and when. Records are
 * upserted by dedupe key, so re-running an import updates rather than
 * duplicates.
 */
const importBase = adminOpportunityCreateSchema.extend({
  externalId: z.string().min(3).max(300).optional(),
  status: z.enum(['draft', 'published', 'archived']).default('published'),
  verificationStatus: z.enum(['verified', 'pending', 'needs_review', 'unverified']),
  lastVerifiedAt: z.coerce.date().nullable().optional(),
  verifiedBy: z.string().min(1).optional(),
  verificationNotes: z.string().max(1000).optional(),
  summarySource: z.enum(['editor', 'ai']).nullable().optional(),
  additionalSources: z.array(z.object({ label: z.string().max(120), url: z.string().url() })).default([]),
});
const requireVerifier = (r, ctx) => {
  if (r.verificationStatus === 'verified' && (!r.lastVerifiedAt || !r.verifiedBy)) {
    ctx.addIssue({ code: 'custom', message: 'Verified records need lastVerifiedAt and verifiedBy', path: ['verificationStatus'] });
  }
};
const importRecord = importBase.superRefine(requireVerifier);

export async function importOpportunities(records, { dryRun = false } = {}) {
  const report = { inserted: 0, updated: 0, rejected: [] };
  for (const [index, raw] of records.entries()) {
    const parsed = importRecord.safeParse(raw);
    if (!parsed.success) {
      report.rejected.push({ index, title: raw?.title ?? null, issues: parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`) });
      continue;
    }
    const r = parsed.data;
    const dedupeKey = buildDedupeKey({ sourceUrl: r.sourceUrl, title: r.title, collegeId: r.collegeId });
    if (dryRun) continue;
    const result = await Opportunity.updateOne(
      { dedupeKey },
      { $set: { ...r, applicationUrl: r.applicationUrl || undefined, dedupeKey, createdBy: r.verifiedBy ?? 'import' } },
      { upsert: true, runValidators: true },
    );
    if (result.upsertedCount) report.inserted += 1;
    else report.updated += 1;
  }
  return report;
}

export async function importColleges(records) {
  let upserted = 0;
  for (const c of records) {
    const normalizedName = normalizeCollegeName(c.name);
    await College.updateOne({ normalizedName }, { $set: { ...c, normalizedName, listed: true } }, { upsert: true });
    upserted += 1;
  }
  return { upserted };
}

export async function importResources(records, verifiedAt = new Date('2026-10-23T12:00:00+05:30')) {
  let upserted = 0;
  for (const r of records) {
    await Resource.updateOne({ url: r.url }, { $set: { ...r, verifiedAt } }, { upsert: true });
    upserted += 1;
  }
  return { upserted };
}

// ---------------------------------------------------------------------------
// Automated (scraped) records
// ---------------------------------------------------------------------------

const AUTO_PREFIX = 'naviq-ingest';
const isAuto = (o) => String(o.verifiedBy ?? '').startsWith(AUTO_PREFIX);

const autoRecord = importBase.extend({ externalId: z.string().min(3).max(300) }).superRefine(requireVerifier);
const datesOnlyRecord = z.object({
  externalId: z.string().min(3),
  datesOnly: z.literal(true),
  deadline: z.coerce.date().nullable().optional(),
  applicationOpensAt: z.coerce.date().nullable().optional(),
  declaredStatus: z.enum(['open', 'closed', 'upcoming', 'unknown']).optional(),
  deadlineNote: z.string().max(300).optional(),
});

/**
 * Merge records produced by the scrapers.
 *  - New external id            -> inserted.
 *  - Existing auto-ingested row -> fully refreshed.
 *  - Existing curated/admin row -> only dates/status are refreshed, so hand-verified
 *    eligibility rules and amounts are never overwritten by automatic extraction.
 */
export async function ingestScrapedRecords(records, { now = new Date() } = {}) {
  const report = { inserted: 0, updated: 0, datesRefreshed: 0, skipped: 0, rejected: [], seen: new Set() };

  for (const [index, raw] of records.entries()) {
    if (raw?.datesOnly) {
      const parsed = datesOnlyRecord.safeParse(raw);
      if (!parsed.success) {
        report.rejected.push({ index, title: raw?.externalId ?? null, issues: parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`) });
        continue;
      }
      const { externalId, datesOnly: _d, ...dates } = parsed.data;
      const res = await Opportunity.updateOne({ externalId }, { $set: { ...dates, datesRefreshedAt: now } });
      if (res.matchedCount) { report.datesRefreshed += 1; report.seen.add(externalId); } else report.skipped += 1;
      continue;
    }

    const parsed = autoRecord.safeParse(raw);
    if (!parsed.success) {
      report.rejected.push({ index, title: raw?.title ?? null, issues: parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`) });
      continue;
    }
    const r = parsed.data;
    const dedupeKey = buildDedupeKey({ sourceUrl: r.sourceUrl, title: r.title, collegeId: null });
    report.seen.add(r.externalId);

    const existing = await Opportunity.findOne({ $or: [{ externalId: r.externalId }, { dedupeKey }] });
    if (!existing) {
      await Opportunity.create({ ...r, applicationUrl: r.applicationUrl || undefined, dedupeKey, datesRefreshedAt: now, createdBy: r.verifiedBy });
      report.inserted += 1;
    } else if (isAuto(existing)) {
      existing.set({ ...r, applicationUrl: r.applicationUrl || undefined, dedupeKey, datesRefreshedAt: now });
      await existing.save();
      report.updated += 1;
    } else {
      existing.set({
        applicationOpensAt: r.applicationOpensAt ?? existing.applicationOpensAt,
        deadline: r.deadline ?? existing.deadline,
        declaredStatus: r.declaredStatus,
        deadlineNote: r.deadlineNote ?? existing.deadlineNote,
        datesRefreshedAt: now,
        externalId: existing.externalId ?? r.externalId,
      });
      await existing.save();
      report.datesRefreshed += 1;
    }
  }
  return report;
}

/**
 * Listings whose source stopped listing them are flagged for review so they
 * leave recommendations. Guarded: if a source returned under half of what we
 * already hold, we assume the page layout changed and retire nothing.
 */
export async function retireMissing({ okSources, seen }) {
  let retired = 0;
  const skippedSources = [];
  for (const sourceId of okSources) {
    const held = await Opportunity.find({ externalId: new RegExp(`^${sourceId}:`), status: 'published' });
    const seenCount = held.filter((o) => seen.has(o.externalId)).length;
    if (held.length && seenCount < held.length * 0.5) { skippedSources.push(sourceId); continue; }
    for (const o of held.filter((x) => !seen.has(x.externalId) && x.verificationStatus !== 'needs_review')) {
      o.verificationStatus = 'needs_review';
      o.declaredStatus = 'unknown';
      o.verificationNotes = `No longer listed by its source on ${new Date().toISOString().slice(0, 10)}. Re-verify before treating as current.`;
      await o.save();
      retired += 1;
    }
  }
  return { retired, skippedSources };
}
