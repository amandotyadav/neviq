/**
 * One-off refresh (also usable from system cron):
 *   npm run refresh
 *   0 3 * * * cd /path/to/server && node scripts/daily-refresh.js
 */
import { env } from '../src/config/env.js';
import { connectDatabase, disconnectDatabase } from '../src/config/db.js';
import { runDailyRefresh } from '../src/ingestion/refresh.js';

await connectDatabase(env.MONGODB_URI);
const run = await runDailyRefresh({ trigger: 'manual' });
console.log(JSON.stringify({ status: run.status, sources: run.sources, inserted: run.inserted, updated: run.updated, datesRefreshed: run.datesRefreshed, retired: run.retired, rejected: run.rejected, linkCheck: run.linkCheck, error: run.error }, null, 2));
await disconnectDatabase();
process.exitCode = run.status === 'failed' ? 1 : 0;
