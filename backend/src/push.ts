// Firebase Cloud Messaging (HTTP v1) from the API: a data-only, high
// priority message wakes the partner's phone when mail lands. The payload
// carries the sealed envelope when it fits, so the phone can show the
// notification without a round trip; it can't be read on the way.

import { importPKCS8, SignJWT } from "jose";

type ServiceAccount = { project_id: string; client_email: string; private_key: string };

const raw = process.env.FIREBASE_SA_B64;
const sa: ServiceAccount | null = raw ? JSON.parse(Buffer.from(raw, "base64").toString("utf8")) : null;

let cached: { token: string; until: number } | null = null;

async function accessToken(): Promise<string> {
  if (cached && Date.now() < cached.until) return cached.token;
  const key = await importPKCS8(sa!.private_key, "RS256");
  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({ scope: "https://www.googleapis.com/auth/firebase.messaging" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(sa!.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!res.ok) throw new Error(`google token ${res.status}`);
  const j = (await res.json()) as { access_token: string; expires_in: number };
  cached = { token: j.access_token, until: Date.now() + (j.expires_in - 120) * 1000 };
  return j.access_token;
}

export const pushEnabled = sa !== null;

export type PushResult = "sent" | "disabled" | "no-token" | "unregistered" | "failed";

/// Sends a wake-up to [token]. "unregistered" means the token is dead.
export async function push(token: string | null, data: Record<string, string>): Promise<PushResult> {
  if (!sa) return "disabled";
  if (!token) return "no-token";
  try {
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: "POST",
      headers: { authorization: `Bearer ${await accessToken()}`, "content-type": "application/json" },
      body: JSON.stringify({ message: { token, data, android: { priority: "high", ttl: "86400s" } } }),
      signal: AbortSignal.timeout(5000),
    });
    if (res.ok) return "sent";
    const text = await res.text();
    if (res.status === 404 || text.includes("UNREGISTERED")) return "unregistered";
    console.error("fcm", res.status, text.slice(0, 300));
    return "failed";
  } catch (e) {
    console.error("fcm", e);
    return "failed";
  }
}
