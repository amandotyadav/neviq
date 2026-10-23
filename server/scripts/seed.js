/**
 * Imports curated colleges, verified learning resources, and verified
 * opportunity records into the configured database.
 *   npm run seed            # uses MONGODB_URI
 *   npm run seed -- --dry   # validate only
 */
import { readFile } from 'node:fs/promises';
import { env } from '../src/config/env.js';
import { connectDatabase, disconnectDatabase } from '../src/config/db.js';
import { importColleges, importOpportunities, importResources } from '../src/ingestion/importer.js';

const load = async (name) => JSON.parse(await readFile(new URL(`../data/${name}`, import.meta.url), 'utf8')).records;

export async function seedAll({ dryRun = false } = {}) {
  const [colleges, resources, opportunities] = await Promise.all([
    load('colleges.json'), load('resources.json'), load('verified-opportunities.json'),
  ]);
  const report = {
    colleges: dryRun ? { skipped: true } : await importColleges(colleges),
    resources: dryRun ? { skipped: true } : await importResources(resources),
    opportunities: await importOpportunities(opportunities, { dryRun }),
  };
  return report;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const dryRun = process.argv.includes('--dry');
  await connectDatabase(env.MONGODB_URI);
  const report = await seedAll({ dryRun });
  console.log(JSON.stringify(report, null, 2));
  await disconnectDatabase();
  if (report.opportunities.rejected.length) process.exitCode = 1;
}
