import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import type { VercelRequest, VercelResponse } from "@vercel/node";
import { users } from "./store.js";
import type { User } from "./types.js";

export function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

export function newId(bytes = 12): string {
  return randomBytes(bytes).toString("base64url");
}

/** Short, human-typeable invite code like "K7M3-PX9Q". */
export function newInviteCode(): string {
  const alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
  const raw = randomBytes(8);
  let code = "";
  for (let i = 0; i < 8; i++) {
    code += alphabet[raw[i] % alphabet.length];
    if (i === 3) code += "-";
  }
  return code;
}

/**
 * Resolves the caller from `Authorization: Bearer <userId>.<token>`.
 * Returns null (and writes a 401) when missing or invalid.
 */
export async function authenticate(req: VercelRequest, res: VercelResponse): Promise<User | null> {
  const header = req.headers.authorization ?? "";
  const match = /^Bearer\s+([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]+)$/.exec(header);
  if (!match) {
    res.status(401).json({ error: "Missing or malformed Authorization header" });
    return null;
  }
  const [, id, token] = match;
  const user = await users.get(id);
  if (!user) {
    res.status(401).json({ error: "Unknown user" });
    return null;
  }
  const expected = Buffer.from(user.tokenHash, "hex");
  const actual = Buffer.from(hashToken(token), "hex");
  if (expected.length !== actual.length || !timingSafeEqual(expected, actual)) {
    res.status(401).json({ error: "Invalid token" });
    return null;
  }
  return user;
}

export function requireCronSecret(req: VercelRequest, res: VercelResponse): boolean {
  const secret = process.env.CRON_SECRET;
  if (!secret || req.headers.authorization !== `Bearer ${secret}`) {
    res.status(401).json({ error: "Unauthorized" });
    return false;
  }
  return true;
}
