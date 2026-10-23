import mongoose from 'mongoose';

const { Schema } = mongoose;

/** One row per automated refresh, so staleness and failures are visible. */
const ingestRunSchema = new Schema(
  {
    startedAt: { type: Date, required: true },
    finishedAt: Date,
    trigger: { type: String, enum: ['schedule', 'manual', 'startup'], default: 'manual' },
    status: { type: String, enum: ['ok', 'partial', 'failed'], required: true },
    sources: [{ id: String, status: String, count: Number, message: String, _id: false }],
    inserted: Number,
    updated: Number,
    datesRefreshed: Number,
    retired: Number,
    rejected: [{ title: String, issues: [String], _id: false }],
    linkCheck: { checked: Number, failing: Number },
    error: String,
  },
  { timestamps: true },
);

ingestRunSchema.index({ startedAt: -1 });

export const IngestRun = mongoose.model('IngestRun', ingestRunSchema);
