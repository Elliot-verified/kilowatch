import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";

process.env.KILOWATCH_STORE = "memory";
process.env.CRON_SECRET = "test-cron-secret";
process.env.MIN_COHORT_SIZE = "20";

const { createServer } = await import("../scripts/dev-server.js");
const server = createServer();
let base = "";

before(async () => {
  await new Promise<void>((resolve) => server.listen(0, resolve));
  base = `http://localhost:${(server.address() as AddressInfo).port}`;
});
after(() => server.close());

async function api(method: string, path: string, token?: string, body?: unknown) {
  const res = await fetch(base + path, {
    method,
    headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null };
}

async function makeUser(name: string, zip: string, kWh: number, privacy?: object) {
  const reg = await api("POST", "/api/register", undefined, { displayName: name });
  assert.equal(reg.status, 201);
  const token: string = reg.body.token;
  const me = await api("PUT", "/api/me", token, { zip, profile: { homeType: "apartment", bedrooms: 1 }, privacy });
  assert.equal(me.status, 200, JSON.stringify(me.body));
  const usage = await api("PUT", "/api/me/usage", token, { periods: [{ periodStart: "2026-09-01", periodEnd: "2026-10-01", kWh }] });
  assert.equal(usage.status, 200, JSON.stringify(usage.body));
  return token;
}

test("end to end: register, submit usage, aggregate, compare, friends, delete", async () => {
  // 24 neighbors using 240..470 kWh for September, plus me at 400.
  for (let i = 0; i < 24; i++) await makeUser(`n${i}`, "11215", 240 + i * 10);
  const me = await makeUser("Elliot", "11215", 400);

  // Nothing published until the cron runs.
  let cmp = await api("GET", "/api/me/comparison?month=2026-09", me);
  assert.equal(cmp.status, 200);
  assert.equal(cmp.body.neighbors, null);

  const unauthorized = await api("GET", "/api/cron/aggregate");
  assert.equal(unauthorized.status, 401);
  const agg = await api("GET", "/api/cron/aggregate", "test-cron-secret");
  assert.equal(agg.status, 200, JSON.stringify(agg.body));
  assert.equal(agg.body.users, 25);
  assert.ok(agg.body.publishedCohorts > 0);

  cmp = await api("GET", "/api/me/comparison?month=2026-09", me);
  assert.ok(cmp.body.neighbors, "cohort of 25 should be published");
  assert.equal(cmp.body.neighbors.householdCount, 25);
  assert.equal(cmp.body.neighbors.cohortDescription, "1-bedroom apartments in 11215");
  assert.equal(cmp.body.neighbors.yourKWh, 400);
  assert.ok(cmp.body.neighbors.percentile > 60 && cmp.body.neighbors.percentile < 95, `percentile ${cmp.body.neighbors.percentile}`);
  assert.ok(cmp.body.neighbors.medianKWh > 300 && cmp.body.neighbors.medianKWh < 400);
  assert.deepEqual(cmp.body.friends, []);

  // Friends: a friend who shares exact usage, and the invite flow.
  const priya = await makeUser("Priya", "11215", 320, { visibleToFriends: true, shareExactUsageWithFriends: true, contributeToNeighborCohort: true });
  const invite = await api("POST", "/api/invites", priya);
  assert.equal(invite.status, 201);
  assert.match(invite.body.code, /^[A-Z2-9]{4}-[A-Z2-9]{4}$/);

  const selfAccept = await api("POST", "/api/invites/accept", priya, { code: invite.body.code });
  assert.equal(selfAccept.status, 400);
  const accept = await api("POST", "/api/invites/accept", me, { code: invite.body.code.toLowerCase() });
  assert.equal(accept.status, 200, JSON.stringify(accept.body));
  assert.equal(accept.body.friend.displayName, "Priya");
  const reuse = await api("POST", "/api/invites/accept", me, { code: invite.body.code });
  assert.equal(reuse.status, 404, "codes are single-use");

  cmp = await api("GET", "/api/me/comparison?month=2026-09", me);
  assert.equal(cmp.body.friends.length, 1);
  assert.equal(cmp.body.friends[0].displayName, "Priya");
  assert.equal(cmp.body.friends[0].kWh, 320);
  assert.ok(Math.abs(cmp.body.friends[0].deltaFromYou - (320 - 400) / 400) < 1e-9);

  // Priya hides herself; she disappears from my comparison.
  await api("PUT", "/api/me", priya, { privacy: { visibleToFriends: false } });
  cmp = await api("GET", "/api/me/comparison?month=2026-09", me);
  assert.equal(cmp.body.friends.length, 0);

  // Turning both toggles off wipes stored usage.
  const off = await api("PUT", "/api/me", priya, { privacy: { contributeToNeighborCohort: false, visibleToFriends: false } });
  assert.deepEqual(off.body.monthsSubmitted, []);

  // Delete me; my token stops working and Priya no longer lists me.
  const del = await api("DELETE", "/api/me", me);
  assert.equal(del.status, 204);
  assert.equal((await api("GET", "/api/me", me)).status, 401);
  assert.equal((await api("GET", "/api/me", priya)).body.friendCount, 0);
});

test("validation and auth errors are clean 4xx responses", async () => {
  assert.equal((await api("GET", "/api/me")).status, 401);
  assert.equal((await api("GET", "/api/me", "bogus.token")).status, 401);
  const reg = await api("POST", "/api/register");
  const token = reg.body.token;
  assert.equal((await api("PUT", "/api/me", token, { zip: "abc" })).status, 400);
  assert.equal((await api("PUT", "/api/me", token, { profile: { homeType: "castle" } })).status, 400);
  assert.equal((await api("PUT", "/api/me/usage", token, { periods: [{ periodStart: "2026-10-01", periodEnd: "2026-09-01", kWh: 1 }] })).status, 400);
  assert.equal((await api("POST", "/api/invites/accept", token, { code: "nope" })).status, 400);
  assert.equal((await api("PATCH", "/api/me", token)).status, 405);
  assert.equal((await api("GET", "/api/health")).status, 200);
});
