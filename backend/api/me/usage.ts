import { route, body } from "../../lib/http.js";
import { authenticate } from "../../lib/auth.js";
import { users } from "../../lib/store.js";
import { parseUsagePeriods } from "../../lib/validate.js";

/**
 * PUT /api/me/usage  { periods: [{ periodStart, periodEnd, kWh }] }
 * Replaces the user's submitted usage. Stored only if some comparison can use it.
 */
export default route({
  async PUT(req, res) {
    const user = await authenticate(req, res);
    if (!user) return;
    if (!user.privacy.contributeToNeighborCohort && !user.privacy.visibleToFriends) {
      res.status(200).json({ stored: 0, reason: "comparisons are off" });
      return;
    }
    user.usage = parseUsagePeriods(body(req).periods);
    await users.save(user);
    res.status(200).json({ stored: Object.keys(user.usage).length, months: Object.keys(user.usage).sort() });
  },
});
