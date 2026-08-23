// Admin login: verify the password against the scrypt hash in ADMIN_PW_HASH and,
// on success, set a signed session cookie. A small fixed delay blunts rapid
// brute-force attempts against a single-password login.
import { verifyPassword, issueCookie } from "../../lib/auth.js";

export default async function handler(req, res) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "method not allowed" });
  }
  const password = req.body && req.body.password ? String(req.body.password) : "";

  await new Promise((r) => setTimeout(r, 400));

  if (!verifyPassword(password)) {
    return res.status(401).json({ error: "invalid password" });
  }
  res.setHeader("Set-Cookie", issueCookie());
  return res.status(200).json({ ok: true });
}
