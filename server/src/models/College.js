import mongoose from 'mongoose';

const { Schema } = mongoose;

/**
 * `listed` colleges are curated with an official website. Students may add
 * an unlisted institution during onboarding; those records are marked
 * `listed: false` until a platform admin reviews them.
 */
const collegeSchema = new Schema(
  {
    name: { type: String, required: true, trim: true, maxlength: 160 },
    normalizedName: { type: String, required: true, unique: true },
    shortName: { type: String, trim: true, maxlength: 30 },
    city: { type: String, trim: true, maxlength: 60 },
    state: { type: String, trim: true, maxlength: 60 },
    website: { type: String, trim: true, maxlength: 300 },
    aliases: [{ type: String, trim: true, lowercase: true }],
    listed: { type: Boolean, default: false },
  },
  { timestamps: true },
);

collegeSchema.index({ name: 'text', aliases: 'text', shortName: 'text' });

export const normalizeCollegeName = (name) =>
  String(name).toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();

export const College = mongoose.model('College', collegeSchema);

export function serializeCollege(c) {
  return {
    id: String(c._id),
    name: c.name,
    shortName: c.shortName ?? null,
    city: c.city ?? null,
    state: c.state ?? null,
    website: c.website ?? null,
    listed: c.listed,
  };
}
