import type { HomeProfile, PrivacySettings, MonthlyUsage } from "./types.js";

export class ValidationError extends Error {}

const HOME_TYPES = new Set(["apartment", "condo", "house"]);

export function parseProfile(input: any, fallback?: HomeProfile): HomeProfile {
  const p = { ...(fallback ?? defaultProfile()), ...(input ?? {}) };
  if (!HOME_TYPES.has(p.homeType)) throw new ValidationError("homeType must be apartment, condo, or house");
  if (!Number.isInteger(p.bedrooms) || p.bedrooms < 0 || p.bedrooms > 20) throw new ValidationError("bedrooms out of range");
  if (!Number.isInteger(p.occupants) || p.occupants < 1 || p.occupants > 30) throw new ValidationError("occupants out of range");
  return {
    homeType: p.homeType,
    bedrooms: p.bedrooms,
    occupants: p.occupants,
    hasCentralAC: Boolean(p.hasCentralAC),
    heatsWithElectricity: Boolean(p.heatsWithElectricity),
  };
}

export function defaultProfile(): HomeProfile {
  return { homeType: "apartment", bedrooms: 1, occupants: 2, hasCentralAC: false, heatsWithElectricity: false };
}

export function parsePrivacy(input: any, fallback?: PrivacySettings): PrivacySettings {
  const p = { ...(fallback ?? defaultPrivacy()), ...(input ?? {}) };
  return {
    contributeToNeighborCohort: Boolean(p.contributeToNeighborCohort),
    visibleToFriends: Boolean(p.visibleToFriends),
    shareExactUsageWithFriends: Boolean(p.shareExactUsageWithFriends),
  };
}

export function defaultPrivacy(): PrivacySettings {
  return { contributeToNeighborCohort: true, visibleToFriends: true, shareExactUsageWithFriends: false };
}

export function parseZip(input: any): string {
  const zip = String(input ?? "").trim();
  if (!/^\d{5}$/.test(zip)) throw new ValidationError("zip must be 5 digits");
  return zip;
}

export function parseDisplayName(input: any): string {
  const name = String(input ?? "").trim().slice(0, 40);
  return name.length > 0 ? name : "Friend";
}

/** The month a billing period belongs to: the one containing its midpoint. */
export function monthKey(periodStart: Date, periodEnd: Date): string {
  const mid = new Date((periodStart.getTime() + periodEnd.getTime()) / 2);
  return `${mid.getUTCFullYear()}-${String(mid.getUTCMonth() + 1).padStart(2, "0")}`;
}

export function parseUsagePeriods(input: any): Record<string, MonthlyUsage> {
  if (!Array.isArray(input)) throw new ValidationError("periods must be an array");
  if (input.length > 60) throw new ValidationError("too many periods");
  const out: Record<string, MonthlyUsage> = {};
  for (const raw of input) {
    const start = new Date(raw?.periodStart);
    const end = new Date(raw?.periodEnd);
    const kWh = Number(raw?.kWh);
    if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime()) || end <= start) throw new ValidationError("bad period dates");
    if (!Number.isFinite(kWh) || kWh < 0 || kWh > 100_000) throw new ValidationError("bad kWh");
    const days = Math.max(1, Math.round((end.getTime() - start.getTime()) / 86_400_000));
    out[monthKey(start, end)] = {
      periodStart: start.toISOString(),
      periodEnd: end.toISOString(),
      kWh,
      days,
      kWhPerDay: kWh / days,
    };
  }
  return out;
}
