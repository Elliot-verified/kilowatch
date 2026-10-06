import type { VercelRequest, VercelResponse } from "@vercel/node";
import { ValidationError } from "./validate.js";

type Handler = (req: VercelRequest, res: VercelResponse) => Promise<void>;

/** Wraps a handler with method checking and uniform error responses. */
export function route(methods: Record<string, Handler>): (req: VercelRequest, res: VercelResponse) => Promise<void> {
  return async (req, res) => {
    const handler = methods[req.method ?? ""];
    if (!handler) {
      res.setHeader("Allow", Object.keys(methods).join(", "));
      res.status(405).json({ error: "Method not allowed" });
      return;
    }
    try {
      await handler(req, res);
    } catch (error: any) {
      if (error instanceof ValidationError) {
        res.status(400).json({ error: error.message });
        return;
      }
      console.error(error);
      res.status(500).json({ error: "Internal error" });
    }
  };
}

export function body(req: VercelRequest): any {
  if (req.body && typeof req.body === "object") return req.body;
  if (typeof req.body === "string" && req.body.length > 0) return JSON.parse(req.body);
  return {};
}
