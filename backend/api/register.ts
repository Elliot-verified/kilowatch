import { route, body } from "../lib/http.js";
import { users } from "../lib/store.js";
import { hashToken, newId } from "../lib/auth.js";
import { defaultProfile, defaultPrivacy, parseDisplayName } from "../lib/validate.js";
import type { User } from "../lib/types.js";

/**
 * POST /api/register  { displayName? }
 * Creates an anonymous user and returns the one-time bearer credential.
 * The token is never stored in the clear; losing it means registering again.
 */
export default route({
  async POST(req, res) {
    const id = newId(12);
    const token = newId(24);
    const now = new Date().toISOString();
    const user: User = {
      id,
      tokenHash: hashToken(token),
      createdAt: now,
      updatedAt: now,
      displayName: parseDisplayName(body(req).displayName),
      zip: "",
      profile: defaultProfile(),
      privacy: defaultPrivacy(),
      usage: {},
      friends: [],
    };
    await users.save(user);
    res.status(201).json({ userId: id, token: `${id}.${token}` });
  },
});
