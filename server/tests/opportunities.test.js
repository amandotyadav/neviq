import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import request from 'supertest';
import { connectTestDb, disconnectTestDb, registerStudent, auth, createOpportunity, createCollege, setProfile } from './helpers.js';

let app;
let student;
let collegeA;
let collegeB;
let opps;

beforeAll(async () => {
  app = await connectTestDb('opps');
  collegeA = await createCollege('Alpha Institute');
  collegeB = await createCollege('Beta Institute');
  student = await registerStudent(app);
  await setProfile(app, student.token, { collegeId: String(collegeA._id), degree: 'B.Tech', branch: 'CSE', currentYear: 2, skills: ['Python', 'Linux'], interests: ['cybersecurity'] });
  opps = {
    security: await createOpportunity({ title: 'Security Research Internship', requiredSkills: ['Linux'], tags: ['cybersecurity'], workMode: 'remote', eligibleYears: [2, 3] }),
    scholarship: await createOpportunity({ title: 'Merit Scholarship', opportunityType: 'scholarship', eligibleYears: [1] }),
    closed: await createOpportunity({ title: 'Closed Hackathon', opportunityType: 'hackathon', deadline: new Date(Date.now() - 86400000) }),
    unverified: await createOpportunity({ title: 'Unverified Listing', verificationStatus: 'unverified' }),
    campusA: await createOpportunity({ title: 'Alpha Campus Drive', collegeId: collegeA._id, sourceType: 'college_admin' }),
    campusB: await createOpportunity({ title: 'Beta Campus Drive', collegeId: collegeB._id, sourceType: 'college_admin' }),
    draft: await createOpportunity({ title: 'Draft Listing', status: 'draft' }),
  };
});
afterAll(disconnectTestDb);

const titles = (res) => res.body.data.map((o) => o.title);

describe('opportunity discovery', () => {
  it('hides closed, draft, and other colleges\' listings by default', async () => {
    const res = await request(app).get('/api/opportunities').set(auth(student.token));
    expect(res.status).toBe(200);
    const t = titles(res);
    expect(t).toContain('Security Research Internship');
    expect(t).toContain('Alpha Campus Drive');
    expect(t).not.toContain('Beta Campus Drive');
    expect(t).not.toContain('Closed Hackathon');
    expect(t).not.toContain('Draft Listing');
  });

  it('includes closed listings only when asked', async () => {
    const res = await request(app).get('/api/opportunities?includeClosed=true').set(auth(student.token));
    expect(titles(res)).toContain('Closed Hackathon');
    expect(res.body.data.find((o) => o.title === 'Closed Hackathon').availability).toBe('closed');
  });

  it('filters by type, search text, work mode, and verified-only', async () => {
    expect(titles(await request(app).get('/api/opportunities?type=scholarship').set(auth(student.token)))).toEqual(['Merit Scholarship']);
    expect(titles(await request(app).get('/api/opportunities?q=security').set(auth(student.token)))).toEqual(['Security Research Internship']);
    expect(titles(await request(app).get('/api/opportunities?workMode=remote').set(auth(student.token)))).toEqual(['Security Research Internship']);
    expect(titles(await request(app).get('/api/opportunities?verifiedOnly=true').set(auth(student.token)))).not.toContain('Unverified Listing');
  });

  it('paginates with metadata', async () => {
    const res = await request(app).get('/api/opportunities?limit=2&page=2').set(auth(student.token));
    expect(res.body.data).toHaveLength(2);
    expect(res.body.meta).toMatchObject({ page: 2, limit: 2 });
    expect(res.body.meta.total).toBeGreaterThanOrEqual(4);
  });

  it('rejects invalid query parameters', async () => {
    expect((await request(app).get('/api/opportunities?type=spaceship').set(auth(student.token))).status).toBe(400);
  });

  it('ranks eligible matches above hard-blocked ones and explains why', async () => {
    const res = await request(app).get('/api/opportunities?sort=relevance').set(auth(student.token));
    const first = res.body.data[0];
    expect(first.match.hardBlocked).toBe(false);
    const scholarship = res.body.data.find((o) => o.title === 'Merit Scholarship');
    expect(scholarship.match.hardBlocked).toBe(true);
    const sec = res.body.data.find((o) => o.title === 'Security Research Internship');
    expect(sec.match.factors.some((f) => f.positive && /Linux/.test(f.detail))).toBe(true);
  });

  it('returns 404 for another college\'s listing (no existence leak)', async () => {
    expect((await request(app).get(`/api/opportunities/${opps.campusB._id}`).set(auth(student.token))).status).toBe(404);
    expect((await request(app).get(`/api/opportunities/${opps.draft._id}`).set(auth(student.token))).status).toBe(404);
  });

  it('recommendations exclude unverified, closed, and ineligible listings', async () => {
    const res = await request(app).get('/api/matches').set(auth(student.token));
    const t = titles(res);
    expect(t).toContain('Security Research Internship');
    expect(t).not.toContain('Unverified Listing');
    expect(t).not.toContain('Closed Hackathon');
    expect(t).not.toContain('Merit Scholarship');
    expect(res.body.meta.excludedIneligible).toBeGreaterThanOrEqual(1);
  });

  it('does not recommend audience-restricted listings, but still lists them in Discover', async () => {
    await createOpportunity({ title: 'Restricted Scholarship', opportunityType: 'scholarship', eligibilityRules: [{ key: 'girl_student', kind: 'self_declared', label: 'Applicant is a girl student', mandatory: true, restrictsAudience: true }] });
    const matches = await request(app).get('/api/matches').set(auth(student.token));
    expect(titles(matches)).not.toContain('Restricted Scholarship');
    expect(matches.body.meta.excludedRestricted).toBe(1);
    const discover = await request(app).get('/api/opportunities?q=Restricted').set(auth(student.token));
    expect(discover.body.data[0].match.audienceRestricted).toBe(true);
  });
});

describe('saving', () => {
  it('saves idempotently, lists, and unsaves', async () => {
    const id = opps.security._id;
    expect((await request(app).post(`/api/opportunities/${id}/save`).set(auth(student.token))).status).toBe(200);
    expect((await request(app).post(`/api/opportunities/${id}/save`).set(auth(student.token))).status).toBe(200);
    const saved = await request(app).get('/api/saved').set(auth(student.token));
    expect(titles(saved)).toEqual(['Security Research Internship']);
    const detail = await request(app).get(`/api/opportunities/${id}`).set(auth(student.token));
    expect(detail.body.data.isSaved).toBe(true);
    await request(app).delete(`/api/opportunities/${id}/save`).set(auth(student.token));
    expect((await request(app).get('/api/saved').set(auth(student.token))).body.data).toEqual([]);
  });

  it('cannot save a listing that is not visible to the student', async () => {
    expect((await request(app).post(`/api/opportunities/${opps.campusB._id}/save`).set(auth(student.token))).status).toBe(404);
  });

  it('keeps saved items private per student', async () => {
    await request(app).post(`/api/opportunities/${opps.security._id}/save`).set(auth(student.token));
    const other = await registerStudent(app);
    expect((await request(app).get('/api/saved').set(auth(other.token))).body.data).toEqual([]);
  });
});

describe('eligibility endpoint', () => {
  it('returns criterion-level results with source caveats', async () => {
    const res = await request(app).post('/api/eligibility/check').set(auth(student.token)).send({ opportunityId: String(opps.security._id) });
    expect(res.status).toBe(200);
    expect(res.body.data.overall).toBe('all_criteria_met');
    expect(res.body.data.criteria.length).toBeGreaterThan(0);
  });

  it('flags expired listings', async () => {
    const res = await request(app).post('/api/eligibility/check').set(auth(student.token)).send({ opportunityId: String(opps.closed._id) });
    expect(res.body.data.caveats.map((c) => c.code)).toContain('closed');
  });
});
