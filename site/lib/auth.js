// Admin auth with no session store: a stateless HMAC-signed cookie. Login
// verifies the password against a scrypt hash held in ADMIN_PW_HASH (never the
// plaintext, and never in the repo), then issues a cookie the API routes verify
// on every request. Secret is ADMIN_SESSION_SECRET.
import crypto from "node:crypto";

const COOKIE = "nsadmin";
const TTL_SECONDS = 12 * 60 * 60; // 12h

// Constant-time scrypt verification against a stored "salt:hash" (both hex).
export function verifyPassword(password) {
  const stored = process.env.ADMIN_PW_HASH || "";
  const [salt, hash] = stored.split(":");
  if (!salt || !hash) return false;
  const derived = crypto.scryptSync(password, salt, hash.length / 2);
  const stored_buf = Buffer.from(hash, "hex");
  if (derived.length !== stored_buf.length) return false;
  return crypto.timingSafeEqual(derived, stored_buf);
}

function sign(value) {
  return crypto
    .createHmac("sha256", process.env.ADMIN_SESSION_SECRET || "")
    .update(value)
    .digest("base64url");
}

export function issueCookie() {
  const exp = String(Math.floor(Date.now() / 1000) + TTL_SECONDS);
  const token = `${exp}.${sign(exp)}`;
  return `${COOKIE}=${token}; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=${TTL_SECONDS}`;
}

export function clearCookie() {
  return `${COOKIE}=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0`;
}

function parseCookies(header) {
  const out = {};
  (header || "").split(";").forEach((part) => {
    const i = part.indexOf("=");
    if (i > -1) out[part.slice(0, i).trim()] = part.slice(i + 1).trim();
  });
  return out;
}

// True only for an unexpired cookie whose signature we minted.
export function isAuthed(req) {
  const token = parseCookies(req.headers.cookie)[COOKIE];
  if (!token) return false;
  const dot = token.indexOf(".");
  if (dot < 0) return false;
  const exp = token.slice(0, dot);
  const sig = token.slice(dot + 1);
  const expected = sign(exp);
  if (
    sig.length !== expected.length ||
    !crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected))
  ) {
    return false;
  }
  return Number(exp) > Math.floor(Date.now() / 1000);
}
