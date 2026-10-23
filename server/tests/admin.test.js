import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import request from 'supertest';
import { connectTestDb, disconnectTestDb, registerStudent, auth, createCollege, makeAdmin, setProfile } from './helpers.js';

let app;
let alpha;
let beta;
let adminA;
let platform;
let studentA;
let studentB;

const listing = (collegeId, extra = {}) => ({
  title: 'Campus Placement Drive 2026',
  organization: 'Alpha Placement Cell',
  opportunityType: 'job',
  sourceUrl: 'https://alpha.example.test/notices/placement-2026',
  collegeId: String(collegeId),
  status: 'published',
  ...extra,
});

beforeAll(async () => {
  app = await connectTestDb('admin');
  alpha = await createCollege('Alpha Institute');
  beta = await createCollege('Beta Institute');
  adminA = await makeAdmin(app, { collegeIds: [alpha._id] });
  platform = await makeAdmin(app, { platform: true });
  studentA = await registerStudent(app);
  studentB = await registerStudent(app);
  await setProfile(app, studentA.token, { collegeId: String(alpha._id) });
  await setProfile(app, studentB.token, { collegeId: String(beta._id) });
});
afterAll(disconnectTestDb);

describe('admin authorization', () => {
  it('blocks students from every admin route', async () => {
    expect((await request(app).get('/api/admin/opportunities').set(auth(studentA.token))).status).toBe(403);
    expect((await request(app).post('/api/admin/announcements').set(auth(studentA.token)).send({ collegeId: String(alpha._id), title: 'Hi there', body: 'x y z' })).status).toBe(403);
    expect((await request(app).get('/api/admin/metrics').set(auth(studentA.token))).status).toBe(403);
  });

  it('lets a college admin publish only for their own college', async () => {
    const own = await request(app).post('/api/admin/opportunities').set(auth(adminA.token)).send(listing(alpha._id));
    expect(own.status).toBe(201);
    expect(own.body.data.verificationStatus).toBe('pending');
    expect(own.body.data.sourceType).toBe('college_admin');
    const other = await request(app).post('/api/admin/opportunities').set(auth(adminA.token)).send(listing(beta._id, { title: 'Sneaky' }));
    expect(other.status).toBe(403);
    const pub = await request(app).post('/api/admin/opportunities').set(auth(adminA.token)).send({ ...listing(alpha._id), collegeId: null, title: 'Public one' });
    expect(pub.status).toBe(403);
  });

  it('requires explicit source confirmation to verify, and re-pends on fact edits', async () => {
    const created = await request(app).post('/api/admin/opportunities').set(auth(adminA.token)).send(listing(alpha._id, { title: 'Verify me', sourceUrl: 'https://alpha.example.test/v' }));
    const id = created.body.data.id;
    expect((await request(app).post(`/api/admin/opportunities/${id}/verify`).set(auth(adminA.token)).send({})).status).toBe(400);
    const verified = await request(app).post(`/api/admin/opportunities/${id}/verify`).set(auth(adminA.token)).send({ sourceConfirmed: true });
    expect(verified.body.data.verificationStatus).toBe('verified');
    expect(verified.body.data.lastVerifiedAt).toBeTruthy();
    const edited = await request(app).patch(`/api/admin/opportunities/${id}`).set(auth(adminA.token)).send({ deadline: new Date(Date.now() + 86400000).toISOString() });
    expect(edited.body.data.verificationStatus).toBe('pending');
  });

  it('prevents editing another college\'s listing and moving listings between colleges', async () => {
    const betaListing = await request(app).post('/api/admin/opportunities').set(auth(platform.token)).send(listing(beta._id, { title: 'Beta drive' }));
    expect(betaListing.status).toBe(201);
    const id = betaListing.body.data.id;
    expect((await request(app).patch(`/api/admin/opportunities/${id}`).set(auth(adminA.token)).send({ title: 'Hijacked' })).status).toBe(403);
    expect((await request(app).post(`/api/admin/opportunities/${id}/verify`).set(auth(adminA.token)).send({ sourceConfirmed: true })).status).toBe(403);
    const own = (await request(app).get('/api/admin/opportunities').set(auth(adminA.token))).body.data[0];
    expect((await request(app).patch(`/api/admin/opportunities/${own.id}`).set(auth(adminA.token)).send({ collegeId: String(beta._id) })).status).toBe(400);
  });

  it('scopes admin listing views to their colleges', async () => {
    const res = await request(app).get('/api/admin/opportunities').set(auth(adminA.token));
    expect(res.body.data.every((o) => o.collegeId === String(alpha._id))).toBe(true);
  });
});

describe('campus announcements', () => {
  it('are visible only to students of the right college, and only once published', async () => {
    const draft = await request(app).post('/api/admin/announcements').set(auth(adminA.token)).send({ collegeId: String(alpha._id), title: 'Scholarship help desk', body: 'The scholarship cell is open 10am–1pm.', category: 'scholarship' });
    expect(draft.status).toBe(201);
    expect(draft.body.data.publishedAt).toBeNull();
    expect((await request(app).get('/api/campus/announcements').set(auth(studentA.token))).body.data).toEqual([]);

    const published = await request(app).patch(`/api/admin/announcements/${draft.body.data.id}`).set(auth(adminA.token)).send({ status: 'published' });
    expect(published.body.data.publishedAt).toBeTruthy();

    const a = await request(app).get('/api/campus/announcements').set(auth(studentA.token));
    expect(a.body.data.map((x) => x.title)).toEqual(['Scholarship help desk']);
    expect(a.body.data[0].collegeName).toBe('Alpha Institute');
    const b = await request(app).get('/api/campus/announcements').set(auth(studentB.token));
    expect(b.body.data).toEqual([]);
  });

  it('blocks announcements for other colleges', async () => {
    const res = await request(app).post('/api/admin/announcements').set(auth(adminA.token)).send({ collegeId: String(beta._id), title: 'Not mine', body: 'Should fail' });
    expect(res.status).toBe(403);
  });

  it('hides expired announcements', async () => {
    await request(app).post('/api/admin/announcements').set(auth(adminA.token)).send({ collegeId: String(alpha._id), title: 'Old notice', body: 'Expired', status: 'published', expiresAt: new Date(Date.now() - 1000).toISOString() });
    const a = await request(app).get('/api/campus/announcements').set(auth(studentA.token));
    expect(a.body.data.map((x) => x.title)).not.toContain('Old notice');
  });
});

describe('admin metrics', () => {
  it('reports aggregate counts only, suppressing small numbers', async () => {
    const own = (await request(app).get('/api/admin/opportunities').set(auth(adminA.token))).body.data.find((o) => o.status === 'published');
    await request(app).post(`/api/opportunities/${own.id}/save`).set(auth(studentA.token));
    const res = await request(app).get('/api/admin/metrics').set(auth(adminA.token));
    expect(res.status).toBe(200);
    const row = res.body.data.listings.find((l) => l.opportunityId === own.id);
    expect(row.saves).toEqual({ count: null, suppressed: true });
    expect(JSON.stringify(res.body)).not.toMatch(/email/i);
  });
});
