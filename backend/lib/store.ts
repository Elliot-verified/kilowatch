/**
 * Persistence on a private Vercel Blob store. Every record is one JSON blob:
 *   users/<id>.json, invites/<code>.json, cohorts/latest.json
 * Concurrency is per-user, so last-write-wins on a single user's document is
 * acceptable. Swap this module for Postgres when scale demands it.
 */
import { put, get, del, list } from "@vercel/blob";
import type { User, Invite, CohortSummary } from "./types.js";

const ACCESS = { access: "private" as const };

async function readJSON<T>(pathname: string): Promise<T | null> {
  try {
    const result = await get(pathname, ACCESS);
    if (!result || result.statusCode !== 200) return null;
    const text = await new Response(result.stream).text();
    return JSON.parse(text) as T;
  } catch (error: any) {
    if (error?.statusCode === 404 || /not found/i.test(String(error?.message))) return null;
    throw error;
  }
}

async function writeJSON(pathname: string, value: unknown): Promise<void> {
  await put(pathname, JSON.stringify(value), {
    ...ACCESS,
    contentType: "application/json",
    addRandomSuffix: false,
    allowOverwrite: true,
    cacheControlMaxAge: 0,
  });
}

async function remove(pathname: string): Promise<void> {
  try {
    await del(pathname, ACCESS as any);
  } catch {
    // Already gone.
  }
}

export const users = {
  path: (id: string) => `users/${id}.json`,
  get: (id: string) => readJSON<User>(users.path(id)),
  save: (user: User) => writeJSON(users.path(user.id), { ...user, updatedAt: new Date().toISOString() }),
  delete: (id: string) => remove(users.path(id)),
  async *all(): AsyncGenerator<User> {
    let cursor: string | undefined;
    do {
      const page = await list({ prefix: "users/", cursor, limit: 250, ...ACCESS } as any);
      for (const blob of page.blobs) {
        const user = await readJSON<User>(blob.pathname);
        if (user) yield user;
      }
      cursor = page.cursor;
    } while (cursor);
  },
};

export const invites = {
  path: (code: string) => `invites/${code}.json`,
  get: (code: string) => readJSON<Invite>(invites.path(code)),
  save: (invite: Invite) => writeJSON(invites.path(invite.code), invite),
  delete: (code: string) => remove(invites.path(code)),
};

export const cohorts = {
  path: "cohorts/latest.json",
  get: () => readJSON<CohortSummary>(cohorts.path),
  save: (summary: CohortSummary) => writeJSON(cohorts.path, summary),
};
