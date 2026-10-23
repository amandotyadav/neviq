/**
 * Local development without MongoDB installed: starts a MongoDB server
 * (mongodb-memory-server) that persists to ./.data/mongo, seeds verified
 * data, and starts the API. For production use MongoDB Atlas via MONGODB_URI.
 *
 *   npm run dev:memory
 *   DEMO_ADMIN_PASSWORD='choose-a-strong-one' npm run dev:memory   # also provisions a KIET admin
 */
import { mkdir } from 'node:fs/promises';
import { MongoMemoryServer } from 'mongodb-memory-server';

const dbPath = new URL('../.data/mongo/', import.meta.url).pathname;
await mkdir(dbPath, { recursive: true });
const mongod = await MongoMemoryServer.create({ instance: { dbPath, storageEngine: 'wiredTiger', port: 27027 } });
process.env.MONGODB_URI = mongod.getUri('naviq');
process.env.JWT_SECRET ??= 'local-dev-only-secret-change-me-0123456789';

process.env.ENABLE_DAILY_REFRESH ??= 'true'; // must be set before config is read
const { start } = await import('../src/server.js');
const { seedAll } = await import('./seed.js');
const { provisionAdmin } = await import('./create-admin.js');

await start();
const report = await seedAll();
console.log('Seed:', JSON.stringify({ colleges: report.colleges, resources: report.resources, opportunities: { inserted: report.opportunities.inserted, updated: report.opportunities.updated, rejected: report.opportunities.rejected.length } }));

if (process.env.DEMO_ADMIN_PASSWORD) {
  const admin = await provisionAdmin({
    email: process.env.DEMO_ADMIN_EMAIL ?? 'campus.admin@kiet.demo',
    name: 'KIET Placement Cell (Demo Admin)',
    password: process.env.DEMO_ADMIN_PASSWORD,
    college: 'KIET Group of Institutions',
  });
  console.log('Admin provisioned:', admin);
}
console.log(`MongoDB (local, persistent): ${process.env.MONGODB_URI}`);

const stop = async () => { await mongod.stop({ doCleanup: false }); };
process.on('SIGINT', stop);
process.on('SIGTERM', stop);
