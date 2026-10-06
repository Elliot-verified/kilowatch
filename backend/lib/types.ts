export type HomeType = "apartment" | "condo" | "house";

export interface HomeProfile {
  homeType: HomeType;
  bedrooms: number;
  occupants: number;
  hasCentralAC: boolean;
  heatsWithElectricity: boolean;
}

export interface PrivacySettings {
  contributeToNeighborCohort: boolean;
  visibleToFriends: boolean;
  shareExactUsageWithFriends: boolean;
}

/** One billing period's usage, keyed by the month containing its midpoint. */
export interface MonthlyUsage {
  periodStart: string; // ISO date
  periodEnd: string;
  kWh: number;
  days: number;
  kWhPerDay: number;
}

export interface User {
  id: string;
  tokenHash: string;
  createdAt: string;
  updatedAt: string;
  displayName: string;
  zip: string;
  profile: HomeProfile;
  privacy: PrivacySettings;
  usage: Record<string, MonthlyUsage>; // "YYYY-MM" -> usage
  friends: string[];
}

export interface Invite {
  code: string;
  fromUserId: string;
  createdAt: string;
  expiresAt: string;
}

/** Aggregated, anonymous statistics for one cohort in one month. */
export interface CohortStats {
  count: number;
  /** kWh per day at the 5th, 10th, ... 95th percentiles (19 values). */
  quantiles: number[];
  medianKWhPerDay: number;
  efficientKWhPerDay: number; // 20th percentile
}

export interface CohortSummary {
  computedAt: string;
  minCohortSize: number;
  cohorts: Record<string, CohortStats>; // "<cohortKey>|<YYYY-MM>" -> stats
}

// Responses sent to the app. Shapes mirror the Swift models.

export interface NeighborComparison {
  cohortDescription: string;
  householdCount: number;
  periodEnd: string;
  yourKWh: number;
  medianKWh: number;
  efficientKWh: number;
  percentile: number;
}

export interface FriendComparison {
  id: string;
  displayName: string;
  deltaFromYou: number;
  sharesExactUsage: boolean;
  kWh: number | null;
}
