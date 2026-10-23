import mongoose from 'mongoose';

const { Schema } = mongoose;

export const ROLES = ['student', 'college_admin', 'platform_admin'];
export const WORK_MODES = ['remote', 'hybrid', 'onsite'];

const projectSchema = new Schema(
  {
    title: { type: String, required: true, trim: true, maxlength: 120 },
    description: { type: String, trim: true, maxlength: 1000 },
    skills: [{ type: String, trim: true, maxlength: 40 }],
    url: { type: String, trim: true, maxlength: 300 },
  },
  { _id: true },
);

const experienceSchema = new Schema(
  {
    role: { type: String, required: true, trim: true, maxlength: 120 },
    organization: { type: String, required: true, trim: true, maxlength: 120 },
    startDate: Date,
    endDate: Date,
    description: { type: String, trim: true, maxlength: 1000 },
  },
  { _id: true },
);

/**
 * Student-editable profile. Every field is optional so onboarding can be
 * skipped and completed later. Sensitive scholarship fields (income, home
 * state) are opt-in and never inferred.
 */
const profileSchema = new Schema(
  {
    collegeId: { type: Schema.Types.ObjectId, ref: 'College', default: null },
    collegeName: { type: String, trim: true, maxlength: 160 },
    degree: { type: String, trim: true, maxlength: 60 },
    branch: { type: String, trim: true, maxlength: 80 },
    currentYear: { type: Number, min: 1, max: 6 },
    semester: { type: Number, min: 1, max: 12 },
    graduationYear: { type: Number, min: 2000, max: 2100 },
    cgpa: { type: Number, min: 0, max: 10 },
    skills: [{ type: String, trim: true, maxlength: 40 }],
    interests: [{ type: String, trim: true, maxlength: 60 }],
    careerGoal: { type: String, trim: true, maxlength: 300 },
    headline: { type: String, trim: true, maxlength: 160 },
    projects: [projectSchema],
    experience: [experienceSchema],
    achievements: [{ type: String, trim: true, maxlength: 300 }],
    preferredLocations: [{ type: String, trim: true, maxlength: 60 }],
    workModes: [{ type: String, enum: WORK_MODES }],
    homeState: { type: String, trim: true, maxlength: 60 },
    annualFamilyIncomeINR: { type: Number, min: 0 },
    links: {
      github: { type: String, trim: true, maxlength: 300 },
      linkedin: { type: String, trim: true, maxlength: 300 },
      portfolio: { type: String, trim: true, maxlength: 300 },
    },
  },
  { _id: false },
);

const userSchema = new Schema(
  {
    email: { type: String, required: true, unique: true, lowercase: true, trim: true, maxlength: 254 },
    passwordHash: { type: String, required: true, select: false },
    name: { type: String, required: true, trim: true, maxlength: 100 },
    // Privileges are never writable through student-facing routes. Admins are
    // provisioned with scripts/create-admin.js.
    role: { type: String, enum: ROLES, default: 'student' },
    adminCollegeIds: [{ type: Schema.Types.ObjectId, ref: 'College' }],
    // Incremented on logout / password change to revoke all issued tokens.
    tokenVersion: { type: Number, default: 0 },
    profile: { type: profileSchema, default: () => ({}) },
    notificationPrefs: {
      deadlineReminders: { type: Boolean, default: true },
      reminderDaysBefore: { type: Number, min: 0, max: 30, default: 3 },
      campusAnnouncements: { type: Boolean, default: true },
    },
    onboardingCompletedAt: Date,
  },
  { timestamps: true },
);

userSchema.index({ 'profile.collegeId': 1 });

export const User = mongoose.model('User', userSchema);

/** Public representation; never includes password hash or token version. */
export function serializeUser(user) {
  const u = user.toObject ? user.toObject() : user;
  return {
    id: String(u._id),
    email: u.email,
    name: u.name,
    role: u.role,
    adminCollegeIds: (u.adminCollegeIds ?? []).map(String),
    profile: { ...u.profile, collegeId: u.profile?.collegeId ? String(u.profile.collegeId) : null },
    notificationPrefs: u.notificationPrefs,
    onboardingCompletedAt: u.onboardingCompletedAt ?? null,
    createdAt: u.createdAt,
  };
}
