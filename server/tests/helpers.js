import { inject } from 'vitest';
import mongoose from 'mongoose';
import request from 'supertest';
import { createApp } from '../src/app.js';
import { User } from '../src/models/User.js';
import { College, normalizeCollegeName } from '../src/models/College.js';
import { Opportunity, buildDedupeKey } from '../src/models/Opportunity.js';

/**
 * Test fixtures are synthetic and live only in the throwaway test database.
 * They are never imported into a real environment.
 */

export async function connectTestDb(name) {
  const uri = inject('mongoUri');
  await mongoose.connect(uri, { dbName: `naviq_test_${name}` });
  await mongoose.connection.dropDatabase();
  await mongoose.syncIndexes();
  return createApp();
}

export async function disconnectTestDb() {
  await mongoose.connection.dropDatabase();
  await mongoose.disconnect();
}

let counter = 0;
export async function registerStudent(app, overrides = {}) {
  counter += 1;
  const body = { name: 'Test Student', email: `student${counter}_${Date.now()}@example.test`, password: 'correct-horse-battery', ...overrides };
  const res = await request(app).post('/api/auth/register').send(body);
  if (res.status !== 201) throw new Error(`register failed: ${res.status} ${JSON.stringify(res.body)}`);
  return { token: res.body.data.token, user: res.body.data.user, email: body.email, password: body.password };
}

export const auth = (token) => ({ Authorization: `Bearer ${token}` });

export async function createCollege(name) {
  return College.create({ name, normalizedName: normalizeCollegeName(name), listed: true });
}

export async function makeAdmin(app, { collegeIds = [], platform = false } = {}) {
  const s = await registerStudent(app, { name: 'Admin Person' });
  await User.updateOne({ _id: s.user.id }, { role: platform ? 'platform_admin' : 'college_admin', adminCollegeIds: collegeIds });
  return s;
}

export async function createOpportunity(overrides = {}) {
  const base = {
    title: `Fixture Opportunity ${Math.random().toString(36).slice(2, 8)}`,
    organization: 'Fixture Org',
    opportunityType: 'internship',
    sourceUrl: `https://fixture.example.test/${Math.random().toString(36).slice(2)}`,
    sourceType: 'official_org_site',
    verificationStatus: 'verified',
    lastVerifiedAt: new Date(),
    declaredStatus: 'open',
    deadline: new Date(Date.now() + 10 * 86400000),
    status: 'published',
    ...overrides,
  };
  return Opportunity.create({ ...base, dedupeKey: buildDedupeKey(base) });
}

export async function setProfile(app, token, profile) {
  const res = await request(app).patch('/api/profile').set(auth(token)).send({ profile });
  if (res.status !== 200) throw new Error(`profile failed: ${res.status} ${JSON.stringify(res.body)}`);
  return res.body.data.user;
}
