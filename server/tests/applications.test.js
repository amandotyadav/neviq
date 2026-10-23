import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import request from 'supertest';
import { connectTestDb, disconnectTestDb, registerStudent, auth, createOpportunity, setProfile } from './helpers.js';

let app;
let alice;
let bob;
let opp;

beforeAll(async () => {
  app = await connectTestDb('apps');
  alice = await registerStudent(app, { name: 'Alice' });
  bob = await registerStudent(app, { name: 'Bob' });
  opp = await createOpportunity({ title: 'Research Fellowship', opportunityType: 'research', deadline: new Date(Date.now() + 5 * 86400000) });
});
afterAll(disconnectTestDb);

describe('application tracker', () => {
  let appId;

  it('creates an application from an opportunity, copying its deadline', async () => {
    const res = await request(app).post('/api/applications').set(auth(alice.token)).send({ opportunityId: String(opp._id), nextAction: 'Ask a teacher for a reference', nextActionDue: new Date(Date.now() + 2 * 86400000).toISOString() });
    expect(res.status).toBe(201);
    expect(res.body.data.status).toBe('interested');
    expect(res.body.data.title).toBe('Research Fellowship');
    expect(new Date(res.body.data.deadline).getTime()).toBe(opp.deadline.getTime());
    appId = res.body.data.id;
  });

  it('prevents tracking the same opportunity twice', async () => {
    const res = await request(app).post('/api/applications').set(auth(alice.token)).send({ opportunityId: String(opp._id) });
    expect(res.status).toBe(409);
  });

  it('creates custom applications without an opportunity', async () => {
    const res = await request(app).post('/api/applications').set(auth(alice.token)).send({ title: 'Campus club internship', organization: 'Robotics Club' });
    expect(res.status).toBe(201);
  });

  it('requires a title or opportunity', async () => {
    expect((await request(app).post('/api/applications').set(auth(alice.token)).send({ notes: 'x' })).status).toBe(400);
  });

  it('updates status with history, notes, and applied date only when the student marks applied', async () => {
    let res = await request(app).patch(`/api/applications/${appId}`).set(auth(alice.token)).send({ status: 'preparing', notes: 'Collect mark sheets' });
    expect(res.body.data.status).toBe('preparing');
    expect(res.body.data.appliedAt).toBeNull();
    res = await request(app).patch(`/api/applications/${appId}`).set(auth(alice.token)).send({ status: 'applied' });
    expect(res.body.data.appliedAt).toBeTruthy();
    expect(res.body.data.statusHistory.map((h) => h.status)).toEqual(['interested', 'preparing', 'applied']);
  });

  it('isolates applications between students', async () => {
    expect((await request(app).get(`/api/applications/${appId}`).set(auth(bob.token))).status).toBe(404);
    expect((await request(app).patch(`/api/applications/${appId}`).set(auth(bob.token)).send({ status: 'withdrawn' })).status).toBe(404);
    expect((await request(app).delete(`/api/applications/${appId}`).set(auth(bob.token))).status).toBe(404);
    expect((await request(app).get('/api/applications').set(auth(bob.token))).body.data).toEqual([]);
  });

  it('archives and lists archived separately', async () => {
    await request(app).patch(`/api/applications/${appId}`).set(auth(alice.token)).send({ archived: true });
    const active = await request(app).get('/api/applications').set(auth(alice.token));
    const archived = await request(app).get('/api/applications?archived=true').set(auth(alice.token));
    expect(active.body.data.map((a) => a.id)).not.toContain(appId);
    expect(archived.body.data.map((a) => a.id)).toContain(appId);
  });

  it('deletes an application', async () => {
    expect((await request(app).delete(`/api/applications/${appId}`).set(auth(alice.token))).status).toBe(200);
    expect((await request(app).get(`/api/applications/${appId}`).set(auth(alice.token))).status).toBe(404);
  });
});

describe('deadlines and next moves', () => {
  it('surface profile gaps first for a new student', async () => {
    const s = await registerStudent(app);
    const res = await request(app).get('/api/me/next-moves').set(auth(s.token));
    expect(res.body.data[0].kind).toBe('complete_profile');
  });

  it('recommend finishing an application with a near deadline and list it in deadlines', async () => {
    const s = await registerStudent(app);
    await setProfile(app, s.token, { degree: 'B.Tech', currentYear: 2, skills: ['Python'], interests: ['research'] });
    await request(app).post('/api/applications').set(auth(s.token)).send({ opportunityId: String(opp._id) });
    const moves = await request(app).get('/api/me/next-moves').set(auth(s.token));
    expect(moves.body.data.some((m) => m.kind === 'deadline_soon')).toBe(true);
    const deadlines = await request(app).get('/api/me/deadlines').set(auth(s.token));
    expect(deadlines.body.data[0]).toMatchObject({ kind: 'application_deadline', title: 'Research Fellowship' });
  });
});

describe('roadmap persistence (no AI needed)', () => {
  it('creates, updates, and completes milestones; isolated per student', async () => {
    let res = await request(app).post('/api/roadmap/milestones').set(auth(alice.token)).send({ goal: 'Cybersecurity internship', title: 'Linux fundamentals', steps: ['Finish OverTheWire Bandit 0–10'], priority: 'high' });
    expect(res.status).toBe(201);
    const milestoneId = res.body.data.milestones[0].id;
    res = await request(app).patch(`/api/roadmap/milestones/${milestoneId}`).set(auth(alice.token)).send({ status: 'completed' });
    expect(res.body.data.milestones[0].status).toBe('completed');
    expect(res.body.data.milestones[0].completedAt).toBeTruthy();
    expect(res.body.data.progress).toEqual({ completed: 1, total: 1 });
    res = await request(app).patch(`/api/roadmap/milestones/${milestoneId}`).set(auth(alice.token)).send({ status: 'paused' });
    expect(res.body.data.milestones[0].completedAt).toBeNull();
    expect((await request(app).patch(`/api/roadmap/milestones/${milestoneId}`).set(auth(bob.token)).send({ status: 'completed' })).status).toBe(404);
    expect((await request(app).get('/api/roadmap').set(auth(bob.token))).body.data).toBeNull();
  });
});
