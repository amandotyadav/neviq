import mongoose from 'mongoose';

const { Schema } = mongoose;

/** Curated learning resources whose URLs were checked by a person. */
const resourceSchema = new Schema(
  {
    title: { type: String, required: true, trim: true },
    provider: { type: String, required: true, trim: true },
    url: { type: String, required: true, unique: true, trim: true },
    skills: [{ type: String, trim: true, lowercase: true }],
    cost: { type: String, enum: ['free', 'freemium', 'paid'], default: 'free' },
    description: { type: String, trim: true, maxlength: 500 },
    verifiedAt: { type: Date, required: true },
  },
  { timestamps: true },
);

export const Resource = mongoose.model('Resource', resourceSchema);

export function serializeResource(r) {
  return {
    id: String(r._id),
    title: r.title,
    provider: r.provider,
    url: r.url,
    skills: r.skills ?? [],
    cost: r.cost,
    description: r.description ?? null,
    verifiedAt: r.verifiedAt,
  };
}
