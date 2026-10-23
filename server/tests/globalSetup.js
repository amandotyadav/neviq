import { MongoMemoryServer } from 'mongodb-memory-server';

/** One throwaway MongoDB for the run; each test file uses its own database. */
export default async function setup({ provide }) {
  const mongod = await MongoMemoryServer.create();
  provide('mongoUri', mongod.getUri());
  return async () => { await mongod.stop(); };
}
