import { Application, PRE_APPLY_STATUSES } from '../models/Application.js';
import { SavedOpportunity } from '../models/SavedOpportunity.js';
import { Opportunity, computeAvailability } from '../models/Opportunity.js';
import { Roadmap } from '../models/Roadmap.js';
import { recommendedMatches } from './opportunities.js';
import { calendarDaysUntil } from '../utils/dates.js';

const DAY = 86400000;
const daysUntil = (d, now) => calendarDaysUntil(d, now);
const plural = (n, w) => `${n} ${w}${n === 1 ? '' : 's'}`;

/**
 * Upcoming dates from the student's own data: tracked application deadlines,
 * next-action due dates, and saved opportunities' verified deadlines.
 */
export async function getDeadlines(user, { now = new Date(), horizonDays = 60 } = {}) {
  const horizon = new Date(now.getTime() + horizonDays * DAY);
  const [apps, saved] = await Promise.all([
    Application.find({ userId: user._id, archived: false }).lean(),
    SavedOpportunity.find({ userId: user._id }).lean(),
  ]);
  const savedOpps = await Opportunity.find({ _id: { $in: saved.map((s) => s.opportunityId) }, status: 'published' }).lean();
  const trackedOppIds = new Set(apps.map((a) => String(a.opportunityId)));
  const out = [];
  for (const a of apps) {
    if (a.deadline && new Date(a.deadline) >= now && new Date(a.deadline) <= horizon && PRE_APPLY_STATUSES.includes(a.status)) {
      out.push({ kind: 'application_deadline', date: a.deadline, title: a.title, organization: a.organization ?? null, applicationId: String(a._id), opportunityId: a.opportunityId ? String(a.opportunityId) : null, status: a.status });
    }
    if (a.nextAction && a.nextActionDue && new Date(a.nextActionDue) <= horizon) {
      out.push({ kind: 'next_action', date: a.nextActionDue, title: a.nextAction, organization: a.title, applicationId: String(a._id), opportunityId: a.opportunityId ? String(a.opportunityId) : null, overdue: new Date(a.nextActionDue) < now, status: a.status });
    }
  }
  for (const o of savedOpps) {
    if (trackedOppIds.has(String(o._id))) continue;
    if (o.deadline && new Date(o.deadline) >= now && new Date(o.deadline) <= horizon) {
      out.push({ kind: 'saved_deadline', date: o.deadline, title: o.title, organization: o.organization, applicationId: null, opportunityId: String(o._id), verified: o.verificationStatus === 'verified' });
    }
  }
  return out.sort((a, b) => new Date(a.date) - new Date(b.date));
}

/**
 * "Your next move": deterministic, explainable recommendations built from
 * real deadlines, application states, saved items, roadmap, and profile gaps.
 */
export async function getNextMoves(user, { now = new Date(), limit = 5 } = {}) {
  const moves = [];
  const p = user.profile ?? {};

  // Profile gaps block eligibility checks — surface them first if severe.
  const missing = [];
  if (!p.degree) missing.push('degree');
  if (!p.currentYear) missing.push('current year');
  if (!p.skills?.length) missing.push('skills');
  if (!p.interests?.length) missing.push('interests');
  if (missing.length) {
    moves.push({
      kind: 'complete_profile',
      priority: missing.length >= 2 ? 95 : 60,
      title: 'Complete your profile',
      detail: `Add your ${missing.join(', ')} so Naviq can check eligibility and explain matches.`,
      reason: 'Eligibility checks show "unknown" without these details.',
      dueAt: null,
      target: { type: 'profile', id: null },
    });
  }

  const apps = await Application.find({ userId: user._id, archived: false }).lean();
  for (const a of apps) {
    if (a.nextAction && a.nextActionDue && new Date(a.nextActionDue) < now) {
      moves.push({
        kind: 'overdue_action', priority: 100,
        title: a.nextAction,
        detail: `${a.title} — this was due ${plural(Math.abs(daysUntil(a.nextActionDue, now)), 'day')} ago.`,
        reason: 'You set this next action yourself and it is overdue.',
        dueAt: a.nextActionDue, target: { type: 'application', id: String(a._id) },
      });
    }
    if (a.deadline && PRE_APPLY_STATUSES.includes(a.status)) {
      const d = daysUntil(a.deadline, now);
      if (d >= 0 && d <= 14) {
        moves.push({
          kind: 'deadline_soon', priority: 90 - d,
          title: a.status === 'ready_to_apply' ? `Submit your application: ${a.title}` : `Finish preparing: ${a.title}`,
          detail: `Deadline in ${plural(d, 'day')}. Status: ${a.status.replaceAll('_', ' ')}.`,
          reason: 'Tracked application with a deadline in the next two weeks.',
          dueAt: a.deadline, target: { type: 'application', id: String(a._id) },
        });
      }
    }
  }

  const tracked = new Set(apps.map((a) => String(a.opportunityId)));
  const saved = await SavedOpportunity.find({ userId: user._id }).lean();
  const savedOpps = await Opportunity.find({ _id: { $in: saved.map((s) => s.opportunityId) }, status: 'published' }).lean();
  for (const o of savedOpps) {
    if (tracked.has(String(o._id)) || computeAvailability(o, now) === 'closed') continue;
    const d = o.deadline ? daysUntil(o.deadline, now) : null;
    moves.push({
      kind: 'track_saved', priority: d != null && d <= 30 ? 75 - d / 2 : 40,
      title: `Start your application: ${o.title}`,
      detail: d != null ? `You saved this. It closes in ${plural(d, 'day')}.` : 'You saved this. Add it to your tracker to plan next steps.',
      reason: 'Saved but not yet tracked.',
      dueAt: o.deadline ?? null, target: { type: 'opportunity', id: String(o._id) },
    });
  }

  const savedIds = new Set(saved.map((s) => String(s.opportunityId)));
  const { items } = await recommendedMatches(user, { limit: 3, now });
  for (const m of items) {
    if (savedIds.has(m.id) || tracked.has(m.id)) continue;
    const d = m.deadline ? daysUntil(m.deadline, now) : null;
    if (d == null || d > 45) continue;
    const why = m.match.factors.find((f) => f.positive)?.detail;
    moves.push({
      kind: 'explore_match', priority: 55 - d / 3,
      title: `Check out: ${m.title}`,
      detail: `${why ?? 'Relevant to your profile.'} Closes in ${plural(d, 'day')}.`,
      reason: 'A verified, open opportunity that matches your profile.',
      dueAt: m.deadline, target: { type: 'opportunity', id: m.id },
    });
    break;
  }

  const roadmap = await Roadmap.findOne({ userId: user._id, status: 'active' }).lean();
  if (roadmap) {
    const order = { high: 0, medium: 1, low: 2 };
    const next = roadmap.milestones
      .filter((m) => m.status === 'in_progress' || m.status === 'not_started')
      .sort((a, b) => (a.status === 'in_progress' ? -1 : 0) - (b.status === 'in_progress' ? -1 : 0) || order[a.priority] - order[b.priority] || a.order - b.order)[0];
    if (next) {
      moves.push({
        kind: 'roadmap', priority: next.status === 'in_progress' ? 50 : 45,
        title: `${next.status === 'in_progress' ? 'Continue' : 'Start'}: ${next.title}`,
        detail: next.steps?.[0] ? `Next step: ${next.steps[0]}` : (next.purpose ?? 'Next milestone on your roadmap.'),
        reason: `From your roadmap: ${roadmap.goal}.`,
        dueAt: next.targetDate ?? null, target: { type: 'milestone', id: String(next._id) },
      });
    }
  } else if (!missing.length) {
    moves.push({
      kind: 'create_roadmap', priority: 30,
      title: 'Create your roadmap',
      detail: p.careerGoal ? `Turn "${p.careerGoal}" into concrete milestones.` : 'Turn your goals into concrete, trackable milestones.',
      reason: 'You do not have an active roadmap yet.',
      dueAt: null, target: { type: 'roadmap', id: null },
    });
  }

  return moves.sort((a, b) => b.priority - a.priority).slice(0, limit).map(({ priority, ...m }) => m);
}
