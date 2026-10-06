import type { User, FriendComparison } from "./types.js";

/**
 * Friend comparisons for one month. Respects the friend's privacy settings:
 * invisible friends are omitted entirely; exact kWh only when they allow it.
 * The difference is normalized per bedroom so a studio and a 3-bedroom
 * compare on a fairer footing.
 */
export function friendComparison(me: User, friend: User, month: string): FriendComparison | null {
  if (!friend.privacy.visibleToFriends) return null;
  const mine = me.usage[month];
  const theirs = friend.usage[month];
  if (!mine || !theirs) return null;
  const myNorm = mine.kWhPerDay / Math.max(1, me.profile.bedrooms);
  const theirNorm = theirs.kWhPerDay / Math.max(1, friend.profile.bedrooms);
  if (!(myNorm > 0)) return null;
  return {
    id: friend.id,
    displayName: friend.displayName,
    deltaFromYou: (theirNorm - myNorm) / myNorm,
    sharesExactUsage: friend.privacy.shareExactUsageWithFriends,
    kWh: friend.privacy.shareExactUsageWithFriends ? theirs.kWh : null,
  };
}
