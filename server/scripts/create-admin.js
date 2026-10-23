/**
 * Provision an administrator. Admin rights can only be granted here — never
 * through the public API.
 *
 *   npm run admin:create -- --email placement@college.edu --name "Placement Cell" \
 *     --college "KIET Group of Institutions" [--password '...'] [--platform]
 *
 * If the email already exists, that account is promoted. Otherwise a new
 * account is created with the given password (min 12 chars).
 */
import { parseArgs } from 'node:util';
import { env } from '../src/config/env.js';
import { connectDatabase, disconnectDatabase } from '../src/config/db.js';
import { User } from '../src/models/User.js';
import { College, normalizeCollegeName } from '../src/models/College.js';
import { hashPassword } from '../src/auth/tokens.js';
import { escapeRegex } from '../src/utils/http.js';

export async function provisionAdmin({ email, name, password, college, platform = false }) {
  if (!email) throw new Error('--email is required');
  let collegeDoc = null;
  if (!platform) {
    if (!college) throw new Error('--college is required for a college admin (or pass --platform)');
    collegeDoc = await College.findOne({ normalizedName: normalizeCollegeName(college) })
      ?? await College.findOne({ $or: [{ shortName: new RegExp(`^${escapeRegex(college)}$`, 'i') }, { name: new RegExp(escapeRegex(college), 'i') }] });
    if (!collegeDoc) throw new Error(`College "${college}" not found. Run the seed or check the name.`);
  }
  let user = await User.findOne({ email: email.toLowerCase() });
  if (!user) {
    if (!password || password.length < 12) throw new Error('New admin accounts need --password with at least 12 characters');
    user = new User({ email, name: name ?? 'Campus Admin', passwordHash: await hashPassword(password) });
  }
  user.role = platform ? 'platform_admin' : 'college_admin';
  if (collegeDoc && !user.adminCollegeIds.some((id) => String(id) === String(collegeDoc._id))) user.adminCollegeIds.push(collegeDoc._id);
  if (collegeDoc && !user.profile?.collegeId) {
    user.profile.collegeId = collegeDoc._id;
    user.profile.collegeName = collegeDoc.name;
  }
  user.tokenVersion += 1; // force re-login so the new role takes effect cleanly
  await user.save();
  return { email: user.email, role: user.role, college: collegeDoc?.name ?? null };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const { values } = parseArgs({
    options: { email: { type: 'string' }, name: { type: 'string' }, password: { type: 'string' }, college: { type: 'string' }, platform: { type: 'boolean', default: false } },
  });
  await connectDatabase(env.MONGODB_URI);
  try {
    console.log(await provisionAdmin(values));
  } catch (err) {
    console.error(`Error: ${err.message}`);
    process.exitCode = 1;
  }
  await disconnectDatabase();
}
