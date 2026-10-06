/**
 * Persistence. Production uses a private Vercel Blob store, one JSON document
 * per record: users/<id>.json, invites/<code>.json, cohorts/latest.json.
 * Concurrency is per-user, so last-write-wins on a single user's document is
 * acceptable. Set KILOWATCH_STORE=memory for local development and tests.
 * This is the only module that knows about Blob; swap it for Postgres here.
 */
import type { User, Invite, CohortSummary } from "./types.js";

export interface Store {
  users: {
    get(id: string): Promise<User | null>;
    save(user: User): Promise<void>;
    delete(id: string): Promise<void>;
    all(): AsyncGenerator<User>;
  };
  invites: {
    get(code: string): Promise<Invite | null>;
    save(invite: Invite): Promise<void>;
    delete(code: string): Promise<void>;
  };
  cohorts: {
    get(): Promise<CohortSummary | null>;
    save(summary: CohortSummary): Promise<void>;
  };
}

function stamped(user: User): User {
  return { ...user, updatedAt: new Date().toISOString() };
}

// MARK: Blob

async function blobStore(): Promise<Store> {
  const { put, get, del, list } = await import("@vercel/blob");
  const ACCESS = { access: "private" as const };

  async function readJSON<T>(pathname: string): Promise<T | null> {
    try {
      // useCache: false bypasses the CDN so reads see the latest write and deletes.
      const result = await get(pathname, { ...ACCESS, useCache: false });
      if (!result || result.statusCode !== 200) return null;
      return JSON.parse(await new Response(result.stream).text()) as T;
    } catch (error: any) {
      if (error?.statusCode === 404 || /not found/i.test(String(error?.message))) return null;
      throw error;
    }
  }
  async function writeJSON(pathname: string, value: unknown): Promise<void> {
    await put(pathname, JSON.stringify(value), {
      ...ACCESS, contentType: "application/json", addRandomSuffix: false, allowOverwrite: true, cacheControlMaxAge: 0,
    });
  }
  async function remove(pathname: string): Promise<void> {
    try { await del(pathname, ACCESS as any); } catch { /* already gone */ }
  }

  return {
    users: {
      get: (id) => readJSON<User>(`users/${id}.json`),
      save: (user) => writeJSON(`users/${user.id}.json`, stamped(user)),
      delete: (id) => remove(`users/${id}.json`),
      async *all() {
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
    },
    invites: {
      get: (code) => readJSON<Invite>(`invites/${code}.json`),
      save: (invite) => writeJSON(`invites/${invite.code}.json`, invite),
      delete: (code) => remove(`invites/${code}.json`),
    },
    cohorts: {
      get: () => readJSON<CohortSummary>("cohorts/latest.json"),
      save: (summary) => writeJSON("cohorts/latest.json", summary),
    },
  };
}

// MARK: Memory

function memoryStore(): Store {
  const users = new Map<string, User>();
  const invites = new Map<string, Invite>();
  let summary: CohortSummary | null = null;
  const clone = <T>(v: T): T => JSON.parse(JSON.stringify(v));
  return {
    users: {
      async get(id) { const u = users.get(id); return u ? clone(u) : null; },
      async save(user) { users.set(user.id, clone(stamped(user))); },
      async delete(id) { users.delete(id); },
      async *all() { for (const u of users.values()) yield clone(u); },
    },
    invites: {
      async get(code) { const i = invites.get(code); return i ? clone(i) : null; },
      async save(invite) { invites.set(invite.code, clone(invite)); },
      async delete(code) { invites.delete(code); },
    },
    cohorts: {
      async get() { return summary ? clone(summary) : null; },
      async save(s) { summary = clone(s); },
    },
  };
}

let storePromise: Promise<Store> | undefined;
export function store(): Promise<Store> {
  if (!storePromise) {
    storePromise = process.env.KILOWATCH_STORE === "memory" ? Promise.resolve(memoryStore()) : blobStore();
  }
  return storePromise;
}

export const users: Store["users"] = {
  get: async (id) => (await store()).users.get(id),
  save: async (user) => (await store()).users.save(user),
  delete: async (id) => (await store()).users.delete(id),
  async *all() { yield* (await store()).users.all(); },
};
export const invites: Store["invites"] = {
  get: async (code) => (await store()).invites.get(code),
  save: async (invite) => (await store()).invites.save(invite),
  delete: async (code) => (await store()).invites.delete(code),
};
export const cohorts: Store["cohorts"] = {
  get: async () => (await store()).cohorts.get(),
  save: async (summary) => (await store()).cohorts.save(summary),
};
