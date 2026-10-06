import { test } from "node:test";
import assert from "node:assert/strict";
import { aggregate, cohortKeys, neighborComparison, percentileOf, statsFor } from "../lib/cohorts.js";
import { friendComparison } from "../lib/friends.js";
import { monthKey, parseUsagePeriods } from "../lib/validate.js";
import type { User } from "../lib/types.js";

function user(id: string, zip: string, kWhPerDay: number, overrides: Partial<User> = {}): User {
  return {
    id, tokenHash: "", createdAt: "", updatedAt: "", displayName: id, zip,
    profile: { homeType: "apartment", bedrooms: 1, occupants: 2, hasCentralAC: false, heatsWithElectricity: false },
    privacy: { contributeToNeighborCohort: true, visibleToFriends: true, shareExactUsageWithFriends: false },
    usage: { "2026-09": { periodStart: "2026-09-01T00:00:00Z", periodEnd: "2026-10-01T00:00:00Z", kWh: kWhPerDay * 30, days: 30, kWhPerDay } },
    friends: [],
    ...overrides,
  };
}

test("cohorts below the minimum size are not published", () => {
  const small = Array.from({ length: 19 }, (_, i) => user(`u${i}`, "11215", 10 + i));
  assert.equal(Object.keys(aggregate(small, 20).cohorts).length, 0);
  const enough = [...small, user("u19", "11215", 30)];
  assert.ok(Object.keys(aggregate(enough, 20).cohorts).length > 0);
});

test("opted-out users are excluded", () => {
  const people = Array.from({ length: 25 }, (_, i) =>
    user(`u${i}`, "11215", 10, { privacy: { contributeToNeighborCohort: i % 5 !== 0, visibleToFriends: true, shareExactUsageWithFriends: false } }));
  const summary = aggregate(people, 20);
  const key = `${cohortKeys("11215", people[0].profile)[0].key}|2026-09`;
  assert.equal(summary.cohorts[key].count, 20);
});

test("percentile interpolates from quantiles", () => {
  const stats = statsFor(Array.from({ length: 100 }, (_, i) => i + 1)); // 1..100 kWh/day
  assert.equal(stats.medianKWhPerDay, 50.5);
  assert.ok(Math.abs(percentileOf(50.5, stats) - 50) <= 1);
  assert.ok(percentileOf(5, stats) <= 6);
  assert.ok(percentileOf(99, stats) >= 94);
});

test("falls back to a broader cohort when the exact one is too small", () => {
  const houses = Array.from({ length: 20 }, (_, i) =>
    user(`h${i}`, "11215", 20, { profile: { homeType: "house", bedrooms: 3, occupants: 4, hasCentralAC: true, heatsWithElectricity: false } }));
  const apartments = Array.from({ length: 5 }, (_, i) => user(`a${i}`, "11215", 10));
  const summary = aggregate([...houses, ...apartments], 20);
  const me = apartments[0];
  const c = neighborComparison(summary, me.zip, me.profile, "2026-09", me.usage["2026-09"]);
  assert.ok(c, "should find the zip-wide cohort");
  assert.equal(c!.cohortDescription, "homes in 11215");
  assert.equal(c!.householdCount, 25);
});

test("friend comparison respects visibility and exact-usage settings", () => {
  const me = user("me", "11215", 10);
  const hidden = user("h", "11215", 5, { privacy: { contributeToNeighborCohort: true, visibleToFriends: false, shareExactUsageWithFriends: true } });
  assert.equal(friendComparison(me, hidden, "2026-09"), null);

  const open = user("o", "11215", 12, { privacy: { contributeToNeighborCohort: true, visibleToFriends: true, shareExactUsageWithFriends: true } });
  const c = friendComparison(me, open, "2026-09")!;
  assert.ok(Math.abs(c.deltaFromYou - 0.2) < 1e-9);
  assert.equal(c.kWh, 360);

  const relative = user("r", "11215", 8);
  assert.equal(friendComparison(me, relative, "2026-09")!.kWh, null);
});

test("usage periods key by the month containing their midpoint", () => {
  assert.equal(monthKey(new Date("2026-09-05T00:00:00Z"), new Date("2026-10-05T00:00:00Z")), "2026-09");
  const parsed = parseUsagePeriods([{ periodStart: "2026-09-05", periodEnd: "2026-10-05", kWh: 300 }]);
  assert.equal(parsed["2026-09"].days, 30);
  assert.equal(parsed["2026-09"].kWhPerDay, 10);
});
