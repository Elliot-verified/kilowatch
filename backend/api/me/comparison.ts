import { route } from "../../lib/http.js";
import { authenticate } from "../../lib/auth.js";
import { users, cohorts } from "../../lib/store.js";
import { neighborComparison } from "../../lib/cohorts.js";
import { friendComparison } from "../../lib/friends.js";

/**
 * GET /api/me/comparison?month=YYYY-MM
 * Neighbor cohort stats (null until a large-enough cohort exists) and
 * comparisons with each friend who has opted in.
 */
export default route({
  async GET(req, res) {
    const user = await authenticate(req, res);
    if (!user) return;
    const month = String(req.query.month ?? Object.keys(user.usage).sort().at(-1) ?? "");
    const usage = user.usage[month];
    if (!usage) {
      res.status(200).json({ month, neighbors: null, friends: [], reason: "no usage submitted for that month" });
      return;
    }

    let neighbors = null;
    if (user.privacy.contributeToNeighborCohort && user.zip) {
      neighbors = neighborComparison(await cohorts.get(), user.zip, user.profile, month, usage);
    }

    const friends = [];
    if (user.privacy.visibleToFriends) {
      for (const friendId of user.friends) {
        const friend = await users.get(friendId);
        if (!friend) continue;
        const c = friendComparison(user, friend, month);
        if (c) friends.push(c);
      }
    }
    res.status(200).json({ month, neighbors, friends });
  },
});
