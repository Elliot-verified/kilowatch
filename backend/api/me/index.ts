import { route, body } from "../../lib/http.js";
import { authenticate } from "../../lib/auth.js";
import { users } from "../../lib/store.js";
import { parseProfile, parsePrivacy, parseZip, parseDisplayName } from "../../lib/validate.js";
import type { User } from "../../lib/types.js";

function publicView(user: User) {
  return {
    userId: user.id,
    displayName: user.displayName,
    zip: user.zip,
    profile: user.profile,
    privacy: user.privacy,
    friendCount: user.friends.length,
    monthsSubmitted: Object.keys(user.usage).sort(),
  };
}

export default route({
  async GET(req, res) {
    const user = await authenticate(req, res);
    if (!user) return;
    res.status(200).json(publicView(user));
  },

  /** PUT /api/me  { displayName?, zip?, profile?, privacy? } */
  async PUT(req, res) {
    const user = await authenticate(req, res);
    if (!user) return;
    const b = body(req);
    if (b.displayName !== undefined) user.displayName = parseDisplayName(b.displayName);
    if (b.zip !== undefined) user.zip = parseZip(b.zip);
    if (b.profile !== undefined) user.profile = parseProfile(b.profile, user.profile);
    if (b.privacy !== undefined) user.privacy = parsePrivacy(b.privacy, user.privacy);
    if (!user.privacy.contributeToNeighborCohort && !user.privacy.visibleToFriends) {
      user.usage = {}; // nothing can use it, so don't keep it
    }
    await users.save(user);
    res.status(200).json(publicView(user));
  },

  /** DELETE /api/me — erases the user and unlinks them from friends. */
  async DELETE(req, res) {
    const user = await authenticate(req, res);
    if (!user) return;
    for (const friendId of user.friends) {
      const friend = await users.get(friendId);
      if (friend) {
        friend.friends = friend.friends.filter((id) => id !== user.id);
        await users.save(friend);
      }
    }
    await users.delete(user.id);
    res.status(204).end();
  },
});
