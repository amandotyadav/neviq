import mongoose from 'mongoose';

const { Schema } = mongoose;

const savedSchema = new Schema(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    opportunityId: { type: Schema.Types.ObjectId, ref: 'Opportunity', required: true },
  },
  { timestamps: true },
);

savedSchema.index({ userId: 1, opportunityId: 1 }, { unique: true });
savedSchema.index({ opportunityId: 1 });

export const SavedOpportunity = mongoose.model('SavedOpportunity', savedSchema);
