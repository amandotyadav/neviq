import mongoose from 'mongoose';

const { Schema } = mongoose;

export const DRAFT_KINDS = ['email', 'cover_letter', 'resume', 'resume_summary'];

/** Generated or hand-written application material. Never sent automatically. */
const draftSchema = new Schema(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    opportunityId: { type: Schema.Types.ObjectId, ref: 'Opportunity', default: null },
    kind: { type: String, enum: DRAFT_KINDS, required: true },
    title: { type: String, trim: true, maxlength: 200 },
    subject: { type: String, trim: true, maxlength: 300 },
    body: { type: String, required: true, maxlength: 20000 },
    generatedBy: { type: String, enum: ['ai', 'student'], default: 'student' },
    aiModel: String,
    missingInformation: [{ type: String, trim: true, maxlength: 300 }],
    reviewedAt: { type: Date, default: null },
  },
  { timestamps: true },
);

draftSchema.index({ userId: 1, updatedAt: -1 });

export const Draft = mongoose.model('Draft', draftSchema);

export function serializeDraft(d) {
  return {
    id: String(d._id),
    opportunityId: d.opportunityId ? String(d.opportunityId) : null,
    kind: d.kind,
    title: d.title ?? null,
    subject: d.subject ?? null,
    body: d.body,
    generatedBy: d.generatedBy,
    missingInformation: d.missingInformation ?? [],
    reviewedAt: d.reviewedAt ?? null,
    createdAt: d.createdAt,
    updatedAt: d.updatedAt,
  };
}
