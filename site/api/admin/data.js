// Admin data endpoint (auth required).
//   GET  -> { leads, threads, repliedThreads }
//   POST { id, replied } -> toggle a reddit thread's replied flag
// Leads and reply-state come from the encrypted blob; the thread list itself is
// the static seed in ../../data/reddit-threads.js.
import { isAuthed } from "../../lib/auth.js";
import { readState, setThreadReplied } from "../../lib/store.js";
import { threads } from "../../data/reddit-threads.js";

export default async function handler(req, res) {
  if (!isAuthed(req)) {
    return res.status(401).json({ error: "unauthorized" });
  }

  if (req.method === "GET") {
    const state = await readState();
    // newest leads first
    const leads = [...state.leads].sort((a, b) => (a.ts < b.ts ? 1 : -1));
    return res.status(200).json({
      leads,
      threads,
      repliedThreads: state.repliedThreads,
    });
  }

  if (req.method === "POST") {
    const id = req.body && req.body.id ? String(req.body.id) : "";
    const replied = !!(req.body && req.body.replied);
    if (!id || !threads.some((t) => t.id === id)) {
      return res.status(400).json({ error: "unknown thread id" });
    }
    const repliedThreads = await setThreadReplied(id, replied);
    return res.status(200).json({ ok: true, repliedThreads });
  }

  res.setHeader("Allow", "GET, POST");
  return res.status(405).json({ error: "method not allowed" });
}
