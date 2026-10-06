/**
 * Minimal local server that routes to the Vercel function handlers with
 * VercelRequest/VercelResponse-compatible shims. Used by the integration
 * test and for `npm run dev`. Not used in production.
 */
import http from "node:http";
import { URL } from "node:url";

type Handler = (req: any, res: any) => Promise<void>;

const routes: Record<string, () => Promise<{ default: Handler }>> = {
  "/api/health": () => import("../api/health.js"),
  "/api/register": () => import("../api/register.js"),
  "/api/me": () => import("../api/me/index.js"),
  "/api/me/usage": () => import("../api/me/usage.js"),
  "/api/me/comparison": () => import("../api/me/comparison.js"),
  "/api/invites": () => import("../api/invites/index.js"),
  "/api/invites/accept": () => import("../api/invites/accept.js"),
  "/api/cron/aggregate": () => import("../api/cron/aggregate.js"),
};

export function createServer(): http.Server {
  return http.createServer(async (req, res) => {
    const url = new URL(req.url ?? "/", "http://localhost");
    const load = routes[url.pathname];
    if (!load) {
      res.statusCode = 404;
      res.end(JSON.stringify({ error: "Not found" }));
      return;
    }
    const chunks: Buffer[] = [];
    for await (const chunk of req) chunks.push(chunk as Buffer);
    const raw = Buffer.concat(chunks).toString("utf8");
    const vreq: any = req;
    vreq.query = Object.fromEntries(url.searchParams);
    vreq.cookies = {};
    vreq.body = raw.length ? JSON.parse(raw) : undefined;
    const vres: any = res;
    vres.status = (code: number) => { res.statusCode = code; return vres; };
    vres.json = (value: unknown) => { res.setHeader("content-type", "application/json"); res.end(JSON.stringify(value)); return vres; };
    vres.send = (value: unknown) => { res.end(typeof value === "string" ? value : JSON.stringify(value)); return vres; };
    const { default: handler } = await load();
    await handler(vreq, vres);
  });
}

if (process.argv[1] && /dev-server\.js$/.test(process.argv[1])) {
  const port = Number(process.env.PORT ?? 3000);
  createServer().listen(port, () => console.log(`kilowatch backend on http://localhost:${port} (store: ${process.env.KILOWATCH_STORE ?? "blob"})`));
}
