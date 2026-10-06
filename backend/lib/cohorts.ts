/**
 * Cohort aggregation and lookup.
 *
 * A cohort is "homes like yours nearby". Only cohorts with at least
 * MIN_COHORT_SIZE contributing households are published, and only as
 * quantiles, so no individual household's usage can be recovered.
 */
import type { HomeProfile, User, CohortStats, CohortSummary, NeighborComparison, MonthlyUsage } from "./types.js";

export const MIN_COHORT_SIZE = Number(process.env.MIN_COHORT_SIZE ?? 20);
const QUANTILE_STEPS = Array.from({ length: 19 }, (_, i) => (i + 1) * 5); // 5, 10, ..., 95

export function bedroomBucket(bedrooms: number): string {
  if (bedrooms <= 1) return "1";
  if (bedrooms === 2) return "2";
  return "3+";
}

/** Cohort keys from most specific to least. The first one that is large enough wins. */
export function cohortKeys(zip: string, profile: HomeProfile): { key: string; description: string }[] {
  const bb = bedroomBucket(profile.bedrooms);
  const bedroomsText = bb === "1" ? "1-bedroom" : bb === "2" ? "2-bedroom" : "3+ bedroom";
  const typeText = profile.homeType === "house" ? "houses" : profile.homeType === "condo" ? "condos" : "apartments";
  const heat = profile.heatsWithElectricity ? "eh" : "ne";
  const heatText = profile.heatsWithElectricity ? " with electric heat" : "";
  return [
    { key: `z5:${zip}|${profile.homeType}|${bb}|${heat}`, description: `${bedroomsText} ${typeText}${heatText} in ${zip}` },
    { key: `z5:${zip}|${profile.homeType}|${bb}`, description: `${bedroomsText} ${typeText} in ${zip}` },
    { key: `z5:${zip}|${profile.homeType}`, description: `${typeText} in ${zip}` },
    { key: `z5:${zip}`, description: `homes in ${zip}` },
    { key: `z3:${zip.slice(0, 3)}|${profile.homeType}|${bb}`, description: `${bedroomsText} ${typeText} near you` },
    { key: `z3:${zip.slice(0, 3)}|${profile.homeType}`, description: `${typeText} near you` },
    { key: `z3:${zip.slice(0, 3)}`, description: "homes near you" },
  ];
}

function quantile(sorted: number[], p: number): number {
  if (sorted.length === 0) return 0;
  const pos = (sorted.length - 1) * (p / 100);
  const lo = Math.floor(pos);
  const hi = Math.ceil(pos);
  if (lo === hi) return sorted[lo];
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
}

export function statsFor(values: number[]): CohortStats {
  const sorted = [...values].sort((a, b) => a - b);
  const quantiles = QUANTILE_STEPS.map((p) => quantile(sorted, p));
  return {
    count: sorted.length,
    quantiles,
    medianKWhPerDay: quantile(sorted, 50),
    efficientKWhPerDay: quantile(sorted, 20),
  };
}

/** Builds the published summary from every contributing user. */
export function aggregate(users: Iterable<User>, minCohortSize = MIN_COHORT_SIZE): CohortSummary {
  const buckets = new Map<string, number[]>();
  for (const user of users) {
    if (!user.privacy.contributeToNeighborCohort) continue;
    if (!/^\d{5}$/.test(user.zip)) continue;
    const keys = cohortKeys(user.zip, user.profile);
    for (const [month, usage] of Object.entries(user.usage)) {
      if (!(usage.kWhPerDay > 0)) continue;
      for (const { key } of keys) {
        const id = `${key}|${month}`;
        const arr = buckets.get(id) ?? [];
        arr.push(usage.kWhPerDay);
        buckets.set(id, arr);
      }
    }
  }
  const cohorts: Record<string, CohortStats> = {};
  for (const [id, values] of buckets) {
    if (values.length >= minCohortSize) cohorts[id] = statsFor(values);
  }
  return { computedAt: new Date().toISOString(), minCohortSize, cohorts };
}

/** Where a value sits in a cohort, 0–100, interpolated from the stored quantiles. */
export function percentileOf(value: number, stats: CohortStats): number {
  const q = stats.quantiles;
  if (value <= q[0]) return Math.round((QUANTILE_STEPS[0] * value) / Math.max(q[0], 1e-9));
  for (let i = 1; i < q.length; i++) {
    if (value <= q[i]) {
      const span = q[i] - q[i - 1];
      const frac = span > 0 ? (value - q[i - 1]) / span : 1;
      return Math.round(QUANTILE_STEPS[i - 1] + frac * (QUANTILE_STEPS[i] - QUANTILE_STEPS[i - 1]));
    }
  }
  return Math.min(99, Math.round(QUANTILE_STEPS[q.length - 1] + 4));
}

export function neighborComparison(
  summary: CohortSummary | null,
  zip: string,
  profile: HomeProfile,
  month: string,
  usage: MonthlyUsage,
): NeighborComparison | null {
  if (!summary) return null;
  for (const { key, description } of cohortKeys(zip, profile)) {
    const stats = summary.cohorts[`${key}|${month}`];
    if (!stats) continue;
    return {
      cohortDescription: description,
      householdCount: stats.count,
      periodEnd: usage.periodEnd,
      yourKWh: usage.kWh,
      medianKWh: stats.medianKWhPerDay * usage.days,
      efficientKWh: stats.efficientKWhPerDay * usage.days,
      percentile: percentileOf(usage.kWhPerDay, stats),
    };
  }
  return null;
}
