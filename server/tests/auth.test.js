import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import request from 'supertest';
import { connectTestDb, disconnectTestDb, registerStudent, auth } from './helpers.js';

let app;
beforeAll(async () => { app = await connectTestDb('auth'); });
afterAll(disconnectTestDb);

describe('authentication', () => {
  it('registers a student and returns a token without the password hash', async () => {
    const res = await request(app).post('/api/auth/register').send({ name: 'Asha', email: 'asha@example.test', password: 'long-enough-pass' });
    expect(res.status).toBe(201);
    expect(res.body.data.token).toBeTruthy();
    expect(res.body.data.user.role).toBe('student');
    expect(JSON.stringify(res.body)).not.toMatch(/passwordHash/);
  });

  it('rejects attempts to self-assign an admin role at registration', async () => {
    const res = await request(app).post('/api/auth/register').send({ name: 'Eve', email: 'eve@example.test', password: 'long-enough-pass', role: 'platform_admin' });
    expect(res.status).toBe(400);
  });

  it('rejects invalid input with field details', async () => {
    const res = await request(app).post('/api/auth/register').send({ name: '', email: 'not-an-email', password: 'short' });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('BAD_REQUEST');
    expect(res.body.error.details.map((d) => d.field)).toEqual(expect.arrayContaining(['name', 'email', 'password']));
  });

  it('rejects duplicate emails', async () => {
    const res = await request(app).post('/api/auth/register').send({ name: 'Asha', email: 'ASHA@example.test', password: 'long-enough-pass' });
    expect(res.status).toBe(409);
  });

  it('logs in with correct credentials and fails with the same message otherwise', async () => {
    const ok = await request(app).post('/api/auth/login').send({ email: 'asha@example.test', password: 'long-enough-pass' });
    expect(ok.status).toBe(200);
    const wrong = await request(app).post('/api/auth/login').send({ email: 'asha@example.test', password: 'nope-nope' });
    const unknown = await request(app).post('/api/auth/login').send({ email: 'nobody@example.test', password: 'nope-nope' });
    expect(wrong.status).toBe(401);
    expect(unknown.status).toBe(401);
    expect(wrong.body.error.message).toBe(unknown.body.error.message);
  });

  it('requires a valid token for protected routes', async () => {
    expect((await request(app).get('/api/auth/me')).status).toBe(401);
    expect((await request(app).get('/api/auth/me').set(auth('garbage'))).status).toBe(401);
  });

  it('logout revokes the token', async () => {
    const s = await registerStudent(app);
    expect((await request(app).get('/api/auth/me').set(auth(s.token))).status).toBe(200);
    expect((await request(app).post('/api/auth/logout').set(auth(s.token))).status).toBe(200);
    expect((await request(app).get('/api/auth/me').set(auth(s.token))).status).toBe(401);
  });

  it('health and readiness endpoints respond', async () => {
    expect((await request(app).get('/health')).body.status).toBe('ok');
    const ready = await request(app).get('/ready');
    expect(ready.status).toBe(200);
    expect(ready.body.database).toBe('connected');
  });
});

describe('profile', () => {
  it('ignores privilege fields and persists profile updates', async () => {
    const s = await registerStudent(app);
    const res = await request(app).patch('/api/profile').set(auth(s.token)).send({
      role: 'platform_admin',
      adminCollegeIds: ['000000000000000000000001'],
      profile: { degree: 'B.Tech', branch: 'CSE', currentYear: 2, skills: ['Python'], interests: ['cybersecurity'] },
    });
    expect(res.status).toBe(200);
    expect(res.body.data.user.role).toBe('student');
    expect(res.body.data.user.adminCollegeIds).toEqual([]);
    const me = await request(app).get('/api/profile').set(auth(s.token));
    expect(me.body.data.user.profile.skills).toEqual(['Python']);
  });

  it('supports institutions that are not listed yet', async () => {
    const s = await registerStudent(app);
    const res = await request(app).patch('/api/profile').set(auth(s.token)).send({ profile: { customCollegeName: 'Example Institute of Technology' } });
    expect(res.status).toBe(200);
    expect(res.body.data.user.profile.collegeName).toBe('Example Institute of Technology');
    expect(res.body.data.user.profile.collegeId).toBeTruthy();
  });

  it('deletes the account and its data after password confirmation', async () => {
    const s = await registerStudent(app);
    expect((await request(app).delete('/api/profile').set(auth(s.token)).send({ password: 'wrong' })).status).toBe(401);
    expect((await request(app).delete('/api/profile').set(auth(s.token)).send({ password: s.password })).status).toBe(200);
    expect((await request(app).post('/api/auth/login').send({ email: s.email, password: s.password })).status).toBe(401);
  });
});
