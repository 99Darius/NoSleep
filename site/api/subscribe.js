// Vercel serverless function: best-effort email capture before download.
// Adds the address as a Resend contact (https://resend.com/docs/api-reference).
// Requires the RESEND_API_KEY env var; without it (or on any upstream error)
// we still return success — the download must never be blocked by this.
export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'method not allowed' });
  }

  const email = (req.body && req.body.email ? String(req.body.email) : '').trim();
  const valid = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email) && email.length <= 254;
  if (!valid) {
    return res.status(400).json({ error: 'invalid email' });
  }

  const key = process.env.RESEND_API_KEY;
  if (key) {
    try {
      const r = await fetch('https://api.resend.com/contacts', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${key}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ email, unsubscribed: false }),
      });
      if (!r.ok) {
        console.error('resend contacts.create failed', r.status, await r.text());
      }
    } catch (err) {
      console.error('resend contacts.create error', err);
    }
  } else {
    console.error('RESEND_API_KEY not set; email not stored:', email);
  }

  return res.status(204).end();
}
