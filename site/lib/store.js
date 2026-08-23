// Tiny encrypted "file" for lead capture + reddit reply-tracking, backed by a
// single Vercel Blob object. No database: we read one blob, mutate it, write it
// back. The payload is AES-256-GCM encrypted with LEADS_ENC_KEY, so even if the
// (private) blob URL ever leaked, the contents are ciphertext.
//
// Concurrency note: this is read-modify-write on one object, so two writes in
// the same instant can race (last writer wins). At this app's signup volume the
// window is negligible; if it ever matters, switch to put()'s ifMatch/ETag.
import crypto from "node:crypto";
import { get, put } from "@vercel/blob";

const BLOB_PATH = "leads.json.enc";
const EMPTY = { leads: [], repliedThreads: {} };

function key() {
  const hex = process.env.LEADS_ENC_KEY;
  if (!hex || hex.length !== 64) {
    throw new Error("LEADS_ENC_KEY missing or not 32 bytes (64 hex chars)");
  }
  return Buffer.from(hex, "hex");
}

// iv(12) | authTag(16) | ciphertext, base64-encoded.
function encrypt(obj) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", key(), iv);
  const data = Buffer.concat([
    cipher.update(JSON.stringify(obj), "utf8"),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();
  return Buffer.concat([iv, tag, data]).toString("base64");
}

function decrypt(b64) {
  const raw = Buffer.from(b64, "base64");
  const iv = raw.subarray(0, 12);
  const tag = raw.subarray(12, 28);
  const data = raw.subarray(28);
  const decipher = crypto.createDecipheriv("aes-256-gcm", key(), iv);
  decipher.setAuthTag(tag);
  const out = Buffer.concat([decipher.update(data), decipher.final()]);
  return JSON.parse(out.toString("utf8"));
}

async function streamToString(stream) {
  const chunks = [];
  for await (const chunk of stream) {
    chunks.push(typeof chunk === "string" ? Buffer.from(chunk) : chunk);
  }
  return Buffer.concat(chunks).toString("utf8");
}

// Reads the encrypted blob and returns the parsed state, or EMPTY if the blob
// doesn't exist yet. A decrypt failure is surfaced (never silently reset to
// empty — that would erase real leads).
export async function readState() {
  const res = await get(BLOB_PATH, { access: "private", useCache: false });
  if (!res || !res.stream) return structuredClone(EMPTY);
  const b64 = await streamToString(res.stream);
  if (!b64.trim()) return structuredClone(EMPTY);
  const state = decrypt(b64);
  return { leads: state.leads || [], repliedThreads: state.repliedThreads || {} };
}

async function writeState(state) {
  await put(BLOB_PATH, encrypt(state), {
    access: "private",
    contentType: "text/plain",
    allowOverwrite: true,
    addRandomSuffix: false,
    cacheControlMaxAge: 0,
  });
}

// Appends a lead if the email isn't already present (case-insensitive). Returns
// true if newly added, false if it was a duplicate.
export async function addLead(email, meta = {}) {
  const state = await readState();
  const lower = email.toLowerCase();
  if (state.leads.some((l) => l.email.toLowerCase() === lower)) return false;
  state.leads.push({
    email,
    ts: new Date().toISOString(),
    source: meta.source || "site",
    ua: meta.ua || "",
  });
  await writeState(state);
  return true;
}

// Toggles the "replied" flag for a reddit thread. `replied` truthy stamps the
// time; falsy clears it.
export async function setThreadReplied(id, replied) {
  const state = await readState();
  if (replied) state.repliedThreads[id] = new Date().toISOString();
  else delete state.repliedThreads[id];
  await writeState(state);
  return state.repliedThreads;
}
