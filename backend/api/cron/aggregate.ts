import { route } from "../../lib/http.js";
import { requireCronSecret } from "../../lib/auth.js";
import { users, cohorts } from "../../lib/store.js";
import { aggregate } from "../../lib/cohorts.js";

export const config = { maxDuration: 300 };

/**
 * GET /api/cron/aggregate — recomputes every cohort from opted-in users.
 * Scheduled in vercel.json; can be triggered manually with the CRON_SECRET.
 */
export default route({
  async GET(req, res) {
    if (!requireCronSecret(req, res)) return;
    const all = [];
    for await (const user of users.all()) all.push(user);
    const summary = aggregate(all);
    await cohorts.save(summary);
    res.status(200).json({
      users: all.length,
      contributors: all.filter((u) => u.privacy.contributeToNeighborCohort).length,
      publishedCohorts: Object.keys(summary.cohorts).length,
      minCohortSize: summary.minCohortSize,
      computedAt: summary.computedAt,
    });
  },
});
