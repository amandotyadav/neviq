import mongoose from 'mongoose';

const { Schema } = mongoose;

export const APPLICATION_STATUSES = [
  'interested',
  'preparing',
  'ready_to_apply',
  'applied',
  'assessment',
  'interview',
  'offer',
  'rejected',
  'withdrawn',
];

/** Statuses that mean the student is still working towards applying. */
export const PRE_APPLY_STATUSES = ['interested', 'preparing', 'ready_to_apply'];

/**
 * A student's own tracker entry. `applied` is only ever set by the student;
 * opening an external link never changes status.
 */
const applicationSchema = new Schema(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    opportunityId: { type: Schema.Types.ObjectId, ref: 'Opportunity', default: null },
    title: { type: String, required: true, trim: true, maxlength: 200 },
    organization: { type: String, trim: true, maxlength: 160 },
    applicationUrl: { type: String, trim: true, maxlength: 500 },
    status: { type: String, enum: APPLICATION_STATUSES, default: 'interested' },
    statusHistory: [{ status: String, at: { type: Date, default: Date.now }, _id: false }],
    notes: { type: String, trim: true, maxlength: 4000 },
    appliedAt: { type: Date, default: null },
    deadline: { type: Date, default: null },
    nextAction: { type: String, trim: true, maxlength: 300 },
    nextActionDue: { type: Date, default: null },
    archived: { type: Boolean, default: false },
  },
  { timestamps: true },
);

applicationSchema.index(
  { userId: 1, opportunityId: 1 },
  { unique: true, partialFilterExpression: { opportunityId: { $type: 'objectId' } } },
);
applicationSchema.index({ userId: 1, archived: 1, updatedAt: -1 });
applicationSchema.index({ opportunityId: 1 });

export const Application = mongoose.model('Application', applicationSchema);

export function serializeApplication(a) {
  return {
    id: String(a._id),
    opportunityId: a.opportunityId ? String(a.opportunityId._id ?? a.opportunityId) : null,
    title: a.title,
    organization: a.organization ?? null,
    applicationUrl: a.applicationUrl ?? null,
    status: a.status,
    statusHistory: (a.statusHistory ?? []).map((h) => ({ status: h.status, at: h.at })),
    notes: a.notes ?? '',
    appliedAt: a.appliedAt ?? null,
    deadline: a.deadline ?? null,
    nextAction: a.nextAction ?? null,
    nextActionDue: a.nextActionDue ?? null,
    archived: a.archived,
    createdAt: a.createdAt,
    updatedAt: a.updatedAt,
  };
}
