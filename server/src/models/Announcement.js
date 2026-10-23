import mongoose from 'mongoose';

const { Schema } = mongoose;

export const ANNOUNCEMENT_CATEGORIES = ['placement', 'scholarship', 'internship', 'event', 'academic', 'general'];

const announcementSchema = new Schema(
  {
    collegeId: { type: Schema.Types.ObjectId, ref: 'College', required: true },
    title: { type: String, required: true, trim: true, maxlength: 160 },
    body: { type: String, required: true, trim: true, maxlength: 5000 },
    category: { type: String, enum: ANNOUNCEMENT_CATEGORIES, default: 'general' },
    sourceUrl: { type: String, trim: true, maxlength: 500 },
    linkedOpportunityId: { type: Schema.Types.ObjectId, ref: 'Opportunity', default: null },
    status: { type: String, enum: ['draft', 'published', 'archived'], default: 'draft' },
    publishedAt: { type: Date, default: null },
    expiresAt: { type: Date, default: null },
    createdBy: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    updatedBy: { type: Schema.Types.ObjectId, ref: 'User' },
    publisherName: { type: String, trim: true },
  },
  { timestamps: true },
);

announcementSchema.index({ collegeId: 1, status: 1, publishedAt: -1 });

export const Announcement = mongoose.model('Announcement', announcementSchema);

export function serializeAnnouncement(a, collegeName) {
  return {
    id: String(a._id),
    collegeId: String(a.collegeId),
    collegeName: collegeName ?? null,
    title: a.title,
    body: a.body,
    category: a.category,
    sourceUrl: a.sourceUrl ?? null,
    linkedOpportunityId: a.linkedOpportunityId ? String(a.linkedOpportunityId) : null,
    status: a.status,
    publishedAt: a.publishedAt ?? null,
    expiresAt: a.expiresAt ?? null,
    publisherName: a.publisherName ?? null,
    createdAt: a.createdAt,
    updatedAt: a.updatedAt,
  };
}
