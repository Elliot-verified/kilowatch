import { route, body } from "../../lib/http.js";
import { authenticate } from "../../lib/auth.js";
import { invites, users } from "../../lib/store.js";
import { ValidationError } from "../../lib/validate.js";

/** POST /api/invites/accept { code } — makes the two users mutual friends. */
export default route({
  async POST(req, res) {
    const user = await authenticate(req, res);
    if (!user) return;
    const code = String(body(req).code ?? "").trim().toUpperCase();
    if (!/^[A-Z2-9]{4}-[A-Z2-9]{4}$/.test(code)) throw new ValidationError("That doesn't look like an invite code");

    const invite = await invites.get(code);
    if (!invite || new Date(invite.expiresAt) < new Date()) {
      res.status(404).json({ error: "That invite has expired or doesn't exist" });
      return;
    }
    if (invite.fromUserId === user.id) throw new ValidationError("You can't accept your own invite");

    const inviter = await users.get(invite.fromUserId);
    if (!inviter) {
      await invites.delete(code);
      res.status(404).json({ error: "The person who sent this invite is no longer on Kilowatch" });
      return;
    }

    if (!user.friends.includes(inviter.id)) user.friends.push(inviter.id);
    if (!inviter.friends.includes(user.id)) inviter.friends.push(user.id);
    await users.save(user);
    await users.save(inviter);
    await invites.delete(code);
    res.status(200).json({ friend: { id: inviter.id, displayName: inviter.displayName } });
  },
});
