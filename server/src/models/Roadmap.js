import mongoose from 'mongoose';

const { Schema } = mongoose;

export const MILESTONE_STATUSES = ['not_started', 'in_progress', 'paused', 'completed'];
export const PRIORITIES = ['high', 'medium', 'low'];

const milestoneSchema = new Schema(
  {
    title: { type: String, required: true, trim: true, maxlength: 160 },
    purpose: { type: String, trim: true, maxlength: 600 },
    steps: [{ type: String, trim: true, maxlength: 300 }],
    skills: [{ type: String, trim: true, maxlength: 40 }],
    // Always presented to students as an estimate.
    effortEstimate: { type: String, trim: true, maxlength: 120 },
    priority: { type: String, enum: PRIORITIES, default: 'medium' },
    order: { type: Number, default: 0 },
    prerequisites: [{ type: String, trim: true, maxlength: 160 }],
    // Catalogue resources with checked URLs.
    verifiedResourceIds: [{ type: Schema.Types.ObjectId, ref: 'Resource' }],
    // Free-text AI suggestions with no verified link.
    suggestedResources: [{ title: String, note: String, _id: false }],
    projectIdeas: [{ type: String, trim: true, maxlength: 300 }],
    targetDate: { type: Date, default: null },
    status: { type: String, enum: MILESTONE_STATUSES, default: 'not_started' },
    completedAt: { type: Date, default: null },
    source: { type: String, enum: ['ai', 'student'], default: 'ai' },
  },
  { timestamps: true },
);

const roadmapSchema = new Schema(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    goal: { type: String, required: true, trim: true, maxlength: 300 },
    summary: { type: String, trim: true, maxlength: 1500 },
    generatedBy: { type: String, enum: ['ai', 'student'], default: 'ai' },
    aiModel: String,
    targetOpportunityId: { type: Schema.Types.ObjectId, ref: 'Opportunity', default: null },
    status: { type: String, enum: ['active', 'archived'], default: 'active' },
    milestones: [milestoneSchema],
  },
  { timestamps: true },
);

roadmapSchema.index({ userId: 1, status: 1 });

export const Roadmap = mongoose.model('Roadmap', roadmapSchema);

export function serializeRoadmap(r, resourcesById = new Map()) {
  const milestones = [...r.milestones].sort((a, b) => a.order - b.order);
  const completed = milestones.filter((m) => m.status === 'completed').length;
  return {
    id: String(r._id),
    goal: r.goal,
    summary: r.summary ?? null,
    generatedBy: r.generatedBy,
    targetOpportunityId: r.targetOpportunityId ? String(r.targetOpportunityId) : null,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
    progress: { completed, total: milestones.length },
    milestones: milestones.map((m) => ({
      id: String(m._id),
      title: m.title,
      purpose: m.purpose ?? null,
      steps: m.steps ?? [],
      skills: m.skills ?? [],
      effortEstimate: m.effortEstimate ?? null,
      priority: m.priority,
      order: m.order,
      prerequisites: m.prerequisites ?? [],
      verifiedResources: (m.verifiedResourceIds ?? [])
        .map((id) => resourcesById.get(String(id)))
        .filter(Boolean),
      suggestedResources: (m.suggestedResources ?? []).map((s) => ({ title: s.title, note: s.note ?? null })),
      projectIdeas: m.projectIdeas ?? [],
      targetDate: m.targetDate ?? null,
      status: m.status,
      completedAt: m.completedAt ?? null,
      source: m.source,
    })),
  };
}
