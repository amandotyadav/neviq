import { execFile } from 'node:child_process';
import { readFile, access } from 'node:fs/promises';
import { promisify } from 'node:util';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { ingestScrapedRecords, retireMissing } from './importer.js';
import { checkSources } from './sourceChecker.js';
import { IngestRun } from '../models/IngestRun.js';
import { logger } from '../utils/logger.js';

const exec = promisify(execFile);
const here = path.dirname(fileURLToPath(import.meta.url));
export const INGEST_DIR = path.resolve(here, '../../../ingest');

async function pythonBin() {
  if (process.env.INGEST_PYTHON) return process.env.INGEST_PYTHON;
  const venv = path.join(INGEST_DIR, '.venv/bin/python');
  try { await access(venv); return venv; } catch { return 'python3'; }
}

/** Runs the Python scrapers and returns their JSON output. */
export async function runScrapers({ timeoutMs = 15 * 60 * 1000 } = {}) {
  const py = await pythonBin();
  await exec(py, ['run.py'], { cwd: INGEST_DIR, timeout: timeoutMs, maxBuffer: 20 * 1024 * 1024 });
  return JSON.parse(await readFile(path.join(INGEST_DIR, 'out/records.json'), 'utf8'));
}

/**
 * One full refresh: scrape -> merge -> retire vanished listings -> link check.
 * Never throws; failures are recorded on the IngestRun.
 * `scraper` is injectable for tests.
 */
export async function runDailyRefresh({ trigger = 'manual', scraper = runScrapers, linkCheck = true } = {}) {
  const startedAt = new Date();
  const run = { startedAt, trigger, status: 'failed', sources: [] };
  try {
    const payload = await scraper();
    run.sources = payload.sources;
    const merge = await ingestScrapedRecords(payload.records, { now: startedAt });
    const okSources = payload.sources.filter((s) => s.status === 'ok').map((s) => s.id);
    const { retired, skippedSources } = await retireMissing({ okSources, seen: merge.seen });
    Object.assign(run, { inserted: merge.inserted, updated: merge.updated, datesRefreshed: merge.datesRefreshed, retired, rejected: merge.rejected.map((r) => ({ title: r.title, issues: r.issues })) });
    if (skippedSources.length) logger.warn('Retirement skipped (source returned far fewer items than held)', { skippedSources });
    if (linkCheck) {
      const checks = await checkSources();
      run.linkCheck = { checked: checks.length, failing: checks.filter((c) => !c.ok).length };
    }
    const failed = payload.sources.filter((s) => s.status === 'error').length;
    run.status = failed || merge.rejected.length ? 'partial' : 'ok';
  } catch (err) {
    run.error = String(err?.message ?? err).slice(0, 500);
    logger.error('Daily refresh failed', { error: err });
  }
  run.finishedAt = new Date();
  await IngestRun.create(run);
  logger.info('Daily refresh finished', { status: run.status, inserted: run.inserted, updated: run.updated, datesRefreshed: run.datesRefreshed, retired: run.retired });
  return run;
}
