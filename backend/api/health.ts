import { route } from "../lib/http.js";
import { cohorts } from "../lib/store.js";

export default route({
  async GET(_req, res) {
    const summary = await cohorts.get();
    res.status(200).json({
      ok: true,
      cohortsComputedAt: summary?.computedAt ?? null,
      publishedCohorts: summary ? Object.keys(summary.cohorts).length : 0,
    });
  },
});
