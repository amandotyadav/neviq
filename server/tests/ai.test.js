import { describe, it, expect, beforeAll, afterAll, afterEach } from 'vitest';
import request from 'supertest';
import { connectTestDb, disconnectTestDb, registerStudent, auth, createOpportunity, setProfile } from './helpers.js';
import { setAIProvider } from '../src/ai/provider.js';
import { AppError } from '../src/utils/errors.js';
import { Resource } from '../src/models/Resource.js';
import { SavedOpportunity } from '../src/models/SavedOpportunity.js';

let app;
let s;
let opp;
let resource;

beforeAll(async () => {
  app = await connectTestDb('ai');
  s = await registerStudent(app, { name: 'Riya Sharma' });
  await setProfile(app, s.token, { degree: 'B.Tech', branch: 'CSE', currentYear: 2, skills: ['Python'], interests: ['cybersecurity'], careerGoal: 'Security analyst' });
  opp = await createOpportunity({ title: 'Security Fellowship', eligibleYears: [2] });
  resource = await Resource.create({ title: 'OWASP Top 10', provider: 'OWASP', url: 'https://owasp.org/www-project-top-ten/', skills: ['cybersecurity'], verifiedAt: new Date() });
});
afterEach(() => setAIProvider(undefined));
afterAll(disconnectTestDb);

/** Scripted fake provider: returns queued responses in order. */
function fakeProvider({ respond = [], structured = [] } = {}) {
  const calls = { respond: [], structured: [] };
  return {
    model: 'fake-model',
    calls,
    async respond(args) {
      calls.respond.push(args);
      const next = respond.shift();
      if (next instanceof Error) throw next;
      return next;
    },
    async structured(args) {
      calls.structured.push(args);
      const next = structured.shift();
      if (next instanceof Error) throw next;
      return next;
    },
  };
}

describe('AI unavailable', () => {
  it('returns a clear 503 when no provider is configured, while other features work', async () => {
    setAIProvider(null);
    const chat = await request(app).post('/api/ai/chat').set(auth(s.token)).send({ messages: [{ role: 'user', content: 'hi' }] });
    expect(chat.status).toBe(503);
    expect(chat.body.error.code).toBe('AI_UNAVAILABLE');
    expect((await request(app).post('/api/ai/roadmap').set(auth(s.token)).send({ goal: 'Cybersecurity' })).status).toBe(503);
    expect((await request(app).get('/api/ai/status').set(auth(s.token))).body.data.available).toBe(false);
    expect((await request(app).get('/api/opportunities').set(auth(s.token))).status).toBe(200);
  });

  it('maps provider failures to a recoverable error and persists nothing', async () => {
    setAIProvider(fakeProvider({ structured: [new AppError(504, 'AI_TIMEOUT', 'Saathi took too long')] }));
    const res = await request(app).post('/api/ai/roadmap').set(auth(s.token)).send({ goal: 'Cybersecurity' });
    expect(res.status).toBe(504);
    expect((await request(app).get('/api/roadmap').set(auth(s.token))).body.data).toBeNull();
  });
});

describe('Saathi chat', () => {
  it('executes read tools as the signed-in user and returns proposals instead of writing', async () => {
    const fake = fakeProvider({
      respond: [
        { text: '', toolCalls: [{ callId: 'c1', name: 'check_eligibility', arguments: JSON.stringify({ opportunity_id: String(opp._id) }) }, { callId: 'c2', name: 'propose_save_opportunity', arguments: JSON.stringify({ opportunity_id: String(opp._id) }) }], rawContent: { role: 'model', parts: [] } },
        { text: 'You meet the year requirement for Security Fellowship. I have prepared a save action for you to confirm.', toolCalls: [], rawContent: undefined },
      ],
    });
    setAIProvider(fake);
    const res = await request(app).post('/api/ai/chat').set(auth(s.token)).send({ messages: [{ role: 'user', content: 'Am I eligible? Save it.' }] });
    expect(res.status).toBe(200);
    expect(res.body.data.toolsUsed).toEqual(['check_eligibility', 'propose_save_opportunity']);
    expect(res.body.data.proposedActions[0]).toMatchObject({ type: 'save_opportunity', opportunityId: String(opp._id) });
    expect(res.body.data.citations[0].title).toBe('Security Fellowship');
    // The proposal did not write anything.
    expect(await SavedOpportunity.countDocuments()).toBe(0);
    // Tool output passed back to the model was the deterministic result.
    const toolOutput = JSON.parse(fake.calls.respond[1].input.find((i) => i.callId === 'c1' && i.type === 'tool_result').output);
    expect(toolOutput.overall).toBe('all_criteria_met');
    // Instructions forbid fabrication and treat source text as untrusted.
    expect(fake.calls.respond[0].instructions).toMatch(/Never invent/);
    expect(fake.calls.respond[0].instructions).toMatch(/untrusted_source_text/);
  });

  it('does not expose other students\' data or hidden listings through tools', async () => {
    const other = await registerStudent(app);
    await request(app).post('/api/applications').set(auth(other.token)).send({ title: 'Secret application' });
    const fake = fakeProvider({
      respond: [
        { text: '', toolCalls: [{ callId: 'a', name: 'get_my_applications', arguments: '{}' }], rawContent: undefined },
        { text: 'You have no tracked applications.', toolCalls: [], rawContent: undefined },
      ],
    });
    setAIProvider(fake);
    await request(app).post('/api/ai/chat').set(auth(s.token)).send({ messages: [{ role: 'user', content: 'Show my applications' }] });
    const out = fake.calls.respond[1].input.find((i) => i.type === 'tool_result').output;
    expect(out).not.toMatch(/Secret application/);
  });
});

describe('roadmap and drafts', () => {
  it('validates AI roadmap output, keeps only catalogue resource ids, and persists it', async () => {
    setAIProvider(fakeProvider({
      structured: [{
        summary: 'A path towards a security internship.',
        milestones: [
          { title: 'Web security basics', purpose: 'Understand common risks', steps: ['Read OWASP Top 10'], skills: ['web security'], effortEstimate: '3–4 hours/week for 2 weeks', priority: 'high', prerequisites: [], verifiedResourceIds: [String(resource._id), 'made-up-id'], suggestedResources: [{ title: 'A YouTube playlist', note: 'search for one' }], projectIdeas: ['Audit a toy app'] },
          { title: 'Linux', purpose: 'CLI fluency', steps: ['Bandit levels'], skills: ['linux'], effortEstimate: '2 hours/week', priority: 'medium', prerequisites: [], verifiedResourceIds: [], suggestedResources: [], projectIdeas: [] },
        ],
      }],
    }));
    const res = await request(app).post('/api/ai/roadmap').set(auth(s.token)).send({ goal: 'Cybersecurity internship' });
    expect(res.status).toBe(201);
    const m = res.body.data.milestones[0];
    expect(m.verifiedResources.map((r) => r.url)).toEqual(['https://owasp.org/www-project-top-ten/']);
    expect(m.suggestedResources[0].title).toBe('A YouTube playlist');
    expect((await request(app).get('/api/roadmap').set(auth(s.token))).body.data.goal).toBe('Cybersecurity internship');
  });

  it('rejects malformed AI output without saving', async () => {
    setAIProvider(fakeProvider({ structured: [{ summary: 'x', milestones: [] }] }));
    const res = await request(app).post('/api/ai/roadmap').set(auth(s.token)).send({ goal: 'Another goal' });
    expect(res.status).toBe(502);
    expect((await request(app).get('/api/roadmap').set(auth(s.token))).body.data.goal).toBe('Cybersecurity internship');
  });

  it('saves AI email drafts as unreviewed and surfaces missing-info placeholders', async () => {
    const fake = fakeProvider({ structured: [{ subject: 'Application: Security Fellowship', body: 'Dear team,\nI am Riya Sharma, a second-year B.Tech CSE student. My CGPA is [ADD: your CGPA].\nRegards', missingInformation: [] }] });
    setAIProvider(fake);
    const res = await request(app).post('/api/ai/draft-email').set(auth(s.token)).send({ opportunityId: String(opp._id) });
    expect(res.status).toBe(201);
    expect(res.body.data.generatedBy).toBe('ai');
    expect(res.body.data.reviewedAt).toBeNull();
    expect(res.body.data.missingInformation).toContain('your CGPA');
    // Model input contained profile facts, but not income or home state.
    const input = JSON.parse(fake.calls.structured[0].input);
    expect(input.student.name).toBe('Riya Sharma');
    expect(input.student).not.toHaveProperty('annualFamilyIncomeINR');
    const reviewed = await request(app).patch(`/api/drafts/${res.body.data.id}`).set(auth(s.token)).send({ markReviewed: true, body: 'Edited by me' });
    expect(reviewed.body.data.reviewedAt).toBeTruthy();
    expect(reviewed.body.data.body).toBe('Edited by me');
  });
});

describe('Gemini message conversion', () => {
  it('maps neutral input to Gemini contents and groups tool results', async () => {
    const { toGeminiContents } = await import('../src/ai/provider.js');
    const raw = { role: 'model', parts: [{ functionCall: { name: 'a', args: {} } }, { functionCall: { name: 'b', args: {} } }] };
    const contents = toGeminiContents([
      { role: 'user', content: 'hi' },
      { role: 'assistant', content: 'hello' },
      { type: 'model_content', content: raw },
      { type: 'tool_result', callId: 'a', name: 'a', output: '{"x":1}' },
      { type: 'tool_result', callId: 'b', name: 'b', output: 'plain' },
    ]);
    expect(contents.map((c) => c.role)).toEqual(['user', 'model', 'model', 'user']);
    expect(contents[3].parts).toHaveLength(2);
    expect(contents[3].parts[0].functionResponse.response).toEqual({ output: { x: 1 } });
    expect(contents[3].parts[1].functionResponse.response).toEqual({ output: 'plain' });
  });
});
