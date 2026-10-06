import { route } from "../../lib/http.js";
import { authenticate, newInviteCode } from "../../lib/auth.js";
import { invites } from "../../lib/store.js";

const INVITE_TTL_DAYS = 14;

/** POST /api/invites — a short code the user shares with a friend. */
export default route({
  async POST(req, res) {
    const user = await authenticate(req, res);
    if (!user) return;
    const code = newInviteCode();
    const now = new Date();
    await invites.save({
      code,
      fromUserId: user.id,
      createdAt: now.toISOString(),
      expiresAt: new Date(now.getTime() + INVITE_TTL_DAYS * 86_400_000).toISOString(),
    });
    res.status(201).json({ code, expiresAt: new Date(now.getTime() + INVITE_TTL_DAYS * 86_400_000).toISOString() });
  },
});
