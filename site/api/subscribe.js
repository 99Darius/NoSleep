// Best-effort email capture before download. Appends the address to the
// encrypted leads blob (see ../lib/store.js). The download must never be blocked
// by this, so any storage error still returns success and is only logged.
import { addLead } from "../lib/store.js";

export default async function handler(req, res) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "method not allowed" });
  }

  const email = (req.body && req.body.email ? String(req.body.email) : "").trim();
  const valid = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email) && email.length <= 254;
  if (!valid) {
    return res.status(400).json({ error: "invalid email" });
  }

  try {
    await addLead(email, {
      source: "site",
      ua: String(req.headers["user-agent"] || "").slice(0, 300),
    });
  } catch (err) {
    console.error("lead capture failed:", err);
  }

  return res.status(204).end();
}
