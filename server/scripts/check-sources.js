/** Refresh link health for all published opportunities. */
import { env } from '../src/config/env.js';
import { connectDatabase, disconnectDatabase } from '../src/config/db.js';
import { checkSources } from '../src/ingestion/sourceChecker.js';

await connectDatabase(env.MONGODB_URI);
const results = await checkSources();
for (const r of results) console.log(`${r.ok ? 'OK  ' : 'FAIL'} ${r.httpStatus ?? '---'} ${r.title}\n     ${r.url}`);
await disconnectDatabase();
