import { Opportunity } from '../models/Opportunity.js';

/**
 * Link-health refresh. This checks that each official source URL still
 * resolves — it does NOT re-verify the facts on the page. Listings whose
 * source is gone (404/410) are moved to `needs_review` so they drop out of
 * recommendations until a person re-verifies them.
 */
export async function checkSources({ fetchImpl = fetch, timeoutMs = 15000 } = {}) {
  const opps = await Opportunity.find({ status: 'published' });
  const results = [];
  const byUrl = new Map(); // many listings share one source page: fetch it once
  for (const opp of opps) {
    let httpStatus = null;
    if (byUrl.has(opp.sourceUrl)) {
      httpStatus = byUrl.get(opp.sourceUrl);
    } else try {
      const res = await fetchImpl(opp.sourceUrl, {
        method: 'GET',
        redirect: 'follow',
        signal: AbortSignal.timeout(timeoutMs),
        headers: { 'user-agent': 'NaviqSourceChecker/1.0 (+link health check)' },
      });
      httpStatus = res.status;
    } catch {
      httpStatus = null;
    }
    byUrl.set(opp.sourceUrl, httpStatus);
    const ok = httpStatus != null && httpStatus < 400;
    opp.lastSourceCheck = { checkedAt: new Date(), httpStatus, ok };
    if (httpStatus === 404 || httpStatus === 410) {
      opp.verificationStatus = 'needs_review';
      opp.verificationNotes = `Source returned HTTP ${httpStatus} on ${new Date().toISOString().slice(0, 10)}. Re-verify before showing as current.`;
    }
    await opp.save();
    results.push({ title: opp.title, url: opp.sourceUrl, httpStatus, ok });
  }
  return results;
}
