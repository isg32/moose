// The Moose API: one Neon Function between the phones and Neon.
//
// Phones sign in to Neon Managed Auth with hidden credentials and send the
// 15-minute JWT here. The API pairs two members into a couple, passes sealed
// mail between them (Postgres, deleted on ack), pushes new mail live over a
// WebSocket fed by Neon Realtime, and signs short-lived URLs for sealed
// media in the private `assets` bucket. It never sees plaintext.

import { randomInt, randomUUID } from "node:crypto";
import {
  DeleteObjectCommand,
  GetObjectCommand,
  PutObjectCommand,
  S3Client,
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { attachDatabasePool } from "@neon/functions";
import { upgradeWebSocket } from "@neon/functions/hono";
import { createRealtime, rawSql } from "@neon/realtime/server";
import { Hono, type Context } from "hono";
import { HTTPException } from "hono/http-exception";
import { createRemoteJWKSet, jwtVerify } from "jose";
import pg from "pg";
import { push, pushEnabled } from "./push.ts";

const env = (key: string): string => {
  const v = process.env[key];
  if (!v) throw new Error(`${key} is not set`);
  return v;
};

// Postgres: one small pool per isolate.
const pool = new pg.Pool({ connectionString: env("DATABASE_URL"), max: 5 });
attachDatabasePool(pool);
const q = <R extends pg.QueryResultRow>(sql: string, params: unknown[] = []) =>
  pool.query<R>(sql, params);

// Managed Auth: verify the JWT against the branch's JWKS.
const authBase = env("NEON_AUTH_BASE_URL");
const issuer = new URL(authBase).origin;
const jwks = createRemoteJWKSet(new URL(env("NEON_AUTH_JWKS_URL")));

async function userFrom(token: string | undefined | null): Promise<string | null> {
  if (!token) return null;
  try {
    const { payload } = await jwtVerify(token, jwks, { issuer, audience: issuer });
    return typeof payload.sub === "string" ? payload.sub : null;
  } catch {
    return null;
  }
}

// Realtime: a direct server, so the API subscribes for the phone and the
// sealed query (a bearer token) never leaves this Function.
const realtimeUrl = process.env.REALTIME_URL ?? process.env.NEON_REALTIME_URL;
const realtimeSecret = process.env.REALTIME_SECRET ?? process.env.NEON_REALTIME_SECRET;
const realtime =
  realtimeUrl && realtimeSecret
    ? createRealtime({ url: realtimeUrl, secret: realtimeSecret, db: new URL(env("DATABASE_URL")).pathname.slice(1) })
    : null;

// Object storage: S3-compatible, path-style, private bucket.
const bucket = process.env.MOOSE_BUCKET ?? "assets";
const s3 = new S3Client({
  endpoint: process.env.AWS_ENDPOINT_URL_S3,
  region: process.env.AWS_REGION ?? "auto",
  forcePathStyle: true,
});

type Mail = { id: string; sender: string; kind: string; body: string; created_at: Date };
type Member = { user_id: string; name: string; pubkey: string; couple_id: string | null; joined_at: Date | null };

const PUSH_KINDS = new Set(["msg", "moment", "call"]);
const KINDS = new Set(["msg", "receipt", "typing", "moment", "theme", "doodle", "rtc", "call"]);
const CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O, 1/I
const MAX_BODY = 256 * 1024; // sealed text and small payloads; media goes to the bucket

const app = new Hono<{ Variables: { user: string } }>();

app.onError((err, c) => {
  if (err instanceof HTTPException) return c.json({ error: err.message }, err.status);
  console.error(err);
  return c.json({ error: "server error" }, 500);
});

app.get("/", (c) =>
  c.json({
    ok: true,
    service: "moose",
    realtime: realtime !== null,
    storage: !!process.env.AWS_ENDPOINT_URL_S3,
    push: pushEnabled,
  }),
);

// Everything below needs a signed-in member: Bearer header, or ?token= on
// the WebSocket (a phone can set headers, but keep one path for both).
app.use("/v1/*", async (c, next) => {
  const header = c.req.header("authorization");
  const token = header?.startsWith("Bearer ") ? header.slice(7) : c.req.query("token");
  const user = await userFrom(token);
  if (!user) return c.json({ error: "unauthorized" }, 401);
  c.set("user", user);
  await next();
});

async function me(c: Context<{ Variables: { user: string } }>): Promise<Member> {
  const { rows } = await q<Member>(
    `insert into members (user_id) values ($1)
     on conflict (user_id) do update set user_id = excluded.user_id
     returning user_id, name, pubkey, couple_id, joined_at`,
    [c.get("user")],
  );
  return rows[0]!;
}

async function partnerOf(m: Member): Promise<Member | null> {
  if (!m.couple_id) return null;
  const { rows } = await q<Member>(
    "select user_id, name, pubkey, couple_id, joined_at from members where couple_id = $1 and user_id <> $2",
    [m.couple_id, m.user_id],
  );
  return rows[0] ?? null;
}

const view = (m: Member, p: Member | null) => ({
  id: m.user_id,
  name: m.name,
  pubkey: m.pubkey,
  coupleId: m.couple_id,
  since: m.joined_at,
  partner: p && { id: p.user_id, name: p.name, pubkey: p.pubkey },
});

async function body<T>(c: Context): Promise<T> {
  try {
    return await c.req.json<T>();
  } catch {
    throw new HTTPException(400, { message: "expected JSON" });
  }
}

// You: name and public key. Called once after sign-up and on rename.
app.get("/v1/me", async (c) => {
  const m = await me(c);
  return c.json(view(m, await partnerOf(m)));
});

app.put("/v1/me", async (c) => {
  const { name, pubkey, fcm } = await body<{ name?: unknown; pubkey?: unknown; fcm?: unknown }>(c);
  if (fcm !== undefined && (typeof fcm !== "string" || fcm.length > 4096))
    throw new HTTPException(400, { message: "fcm" });
  if (name !== undefined && (typeof name !== "string" || name.length > 40))
    throw new HTTPException(400, { message: "name" });
  if (pubkey !== undefined && (typeof pubkey !== "string" || pubkey.length > 100))
    throw new HTTPException(400, { message: "pubkey" });
  await me(c);
  const { rows } = await q<Member>(
    `update members set name = coalesce($2, name), pubkey = coalesce($3, pubkey),
       fcm_token = case when $4::text is null then fcm_token else nullif($4, '') end
     where user_id = $1 returning user_id, name, pubkey, couple_id, joined_at`,
    [c.get("user"), name ?? null, pubkey ?? null, fcm ?? null],
  );
  return c.json(view(rows[0]!, await partnerOf(rows[0]!)));
});

// Pairing (C5–C10). The new phone shows a code; the other phone joins it.
// If the joiner is already paired, the code's creator takes the place of
// the joiner's old phone: that is the re-pair after a lost phone.
app.post("/v1/invites", async (c) => {
  const m = await me(c);
  if (m.couple_id && (await partnerOf(m))) throw new HTTPException(409, { message: "already paired" });
  await q("delete from invites where creator = $1 or expires_at < now()", [m.user_id]);
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = Array.from({ length: 6 }, () => CODE_CHARS[randomInt(CODE_CHARS.length)]).join("");
    const { rowCount } = await q(
      `insert into invites (code, creator, expires_at) values ($1, $2, now() + interval '10 minutes')
       on conflict do nothing`,
      [code, m.user_id],
    );
    if (rowCount) return c.json({ code, expiresIn: 600 });
  }
  throw new HTTPException(503, { message: "try again" });
});

app.post("/v1/join", async (c) => {
  const { code } = await body<{ code?: unknown }>(c);
  if (typeof code !== "string" || !/^[A-Z0-9]{6}$/.test(code.toUpperCase()))
    throw new HTTPException(400, { message: "code" });
  const joiner = await me(c);
  const db = await pool.connect();
  try {
    await db.query("begin");
    const inv = await db.query<{ creator: string }>(
      "delete from invites where code = $1 and expires_at > now() returning creator",
      [code.toUpperCase()],
    );
    const creator = inv.rows[0]?.creator;
    if (!creator) throw new HTTPException(404, { message: "expired" });
    if (creator === joiner.user_id) throw new HTTPException(400, { message: "your own code" });
    let couple = joiner.couple_id;
    if (couple) {
      // Re-pair: the creator replaces the joiner's old phone.
      await db.query("update members set couple_id = null, joined_at = null where couple_id = $1 and user_id <> $2", [
        couple,
        joiner.user_id,
      ]);
      await db.query("delete from mailbox where couple_id = $1", [couple]);
    } else {
      const made = await db.query<{ id: string }>("insert into couples default values returning id");
      couple = made.rows[0]!.id;
      await db.query("update members set couple_id = $1, joined_at = now() where user_id = $2", [couple, joiner.user_id]);
    }
    await db.query("update members set couple_id = $1, joined_at = now() where user_id = $2", [couple, creator]);
    await db.query("commit");
  } catch (e) {
    await db.query("rollback");
    throw e;
  } finally {
    db.release();
  }
  const m = await me(c);
  return c.json(view(m, await partnerOf(m)));
});

app.post("/v1/unpair", async (c) => {
  const m = await me(c);
  if (m.couple_id) await q("delete from couples where id = $1", [m.couple_id]);
  return c.json({ ok: true });
});

// Mail: sealed envelopes to the partner, kept until acked.
app.post("/v1/mail", async (c) => {
  const { id, kind, body: sealed } = await body<{ id?: unknown; kind?: unknown; body?: unknown }>(c);
  if (typeof id !== "string" || !/^[0-9a-f-]{36}$/i.test(id)) throw new HTTPException(400, { message: "id" });
  if (typeof kind !== "string" || !KINDS.has(kind)) throw new HTTPException(400, { message: "kind" });
  if (typeof sealed !== "string" || sealed.length > MAX_BODY) throw new HTTPException(400, { message: "body" });
  // One statement: the membership rows supply couple and recipient, so only
  // a paired member can write, and only to their partner.
  const { rows } = await q<{ txid: string; recipient: string; token: string | null; sender: string }>(
    `with ins as (
       insert into mailbox (id, couple_id, sender, recipient, kind, body)
       select $1::uuid, me.couple_id, me.user_id, them.user_id, $3, $4
       from members me join members them on them.couple_id = me.couple_id and them.user_id <> me.user_id
       where me.user_id = $2
       on conflict (id) do nothing
       returning recipient, pg_current_xact_id()::text as txid
     )
     select ins.txid, ins.recipient, them.fcm_token as token, me.name as sender
     from ins join members them on them.user_id = ins.recipient join members me on me.user_id = $2`,
    [id, c.get("user"), kind, sealed],
  );
  const sent = rows[0];
  if (!sent) {
    const m = await me(c);
    if (!(await partnerOf(m))) throw new HTTPException(409, { message: "not paired" });
    return c.json({ kind: "duplicate" });
  }
  // Wake the other phone for what a person would want to know about.
  let pushed: string = "skipped";
  if (PUSH_KINDS.has(kind)) {
    pushed = await push(sent.token, {
      kind,
      id,
      from: sent.sender,
      ...(sealed.length <= 3000 ? { body: sealed } : {}),
    });
    if (pushed === "unregistered")
      await q("update members set fcm_token = null where user_id = $1", [sent.recipient]);
  }
  return c.json({ kind: "committed", txid: sent.txid, pushed });
});

// The background check (every 6 min) and the open app's fallback.
app.get("/v1/mail", async (c) => {
  const { rows } = await q<Mail>(
    "select id, sender, kind, body, created_at from mailbox where recipient = $1 order by created_at limit 500",
    [c.get("user")],
  );
  return c.json(rows);
});

app.post("/v1/mail/ack", async (c) => {
  const { ids } = await body<{ ids?: unknown }>(c);
  if (!Array.isArray(ids) || ids.length > 500 || !ids.every((x) => typeof x === "string" && /^[0-9a-f-]{36}$/i.test(x)))
    throw new HTTPException(400, { message: "ids" });
  const { rowCount } = await q("delete from mailbox where recipient = $1 and id = any($2::uuid[])", [c.get("user"), ids]);
  // Nothing should sit here long: drop anything a month old.
  await q("delete from mailbox where created_at < now() - interval '30 days'");
  return c.json({ deleted: rowCount ?? 0 });
});

// Live mail over a WebSocket. Neon Realtime watches this member's mailbox;
// each new row is pushed as {"type":"mail", ...}. Typing and call signals
// travel as mail too, so they survive isolate hops.
app.get(
  "/v1/live",
  upgradeWebSocket((c) => {
    const user = c.get("user");
    let stop: (() => void) | undefined;
    let beat: ReturnType<typeof setInterval> | undefined;
    return {
      async onOpen(_e, ws) {
        beat = setInterval(() => ws.send('{"type":"ping"}'), 25_000);
        if (!realtime) {
          ws.send('{"type":"poll"}'); // no Realtime: the phone falls back to polling
          return;
        }
        const sub = await realtime.subscribe(
          rawSql<Mail>(
            "SELECT id, sender, kind, body, created_at FROM mailbox WHERE recipient = $1",
            [user],
          ),
          { materialize: false },
        );
        const send = (m: Mail) => ws.send(JSON.stringify({ type: "mail", ...m }));
        const offUpdate = sub.onUpdate((u) => {
          if (u.type === "rows") for (const { row } of u.rows) send(row);
          else for (const ch of u.changes) if (ch.type === "upsert") send(ch.row);
        });
        const offState = sub.onStateChange((s) => {
          ws.send(JSON.stringify({ type: "state", status: s.status }));
          if (s.status === "error") ws.close(1011, "realtime");
        });
        stop = () => {
          offUpdate();
          offState();
          sub.unsubscribe();
        };
      },
      onClose() {
        clearInterval(beat);
        stop?.();
      },
    };
  }),
);

// Sealed media in the private bucket: the phone encrypts, PUTs to a signed
// URL, and sends the key inside a sealed message. The receiver GETs and
// then deletes it. Keys live under the couple, so only the pair can sign.
async function coupleOf(c: Context<{ Variables: { user: string } }>): Promise<string> {
  const m = await me(c);
  if (!m.couple_id) throw new HTTPException(409, { message: "not paired" });
  return m.couple_id;
}

function ownKey(couple: string, key: unknown): string {
  if (typeof key !== "string" || !key.startsWith(`c/${couple}/`) || !/^c\/[0-9a-f-]{36}\/[0-9a-f-]{36}$/.test(key))
    throw new HTTPException(403, { message: "key" });
  return key;
}

app.post("/v1/blobs", async (c) => {
  const couple = await coupleOf(c);
  const key = `c/${couple}/${randomUUID()}`;
  const url = await getSignedUrl(s3, new PutObjectCommand({ Bucket: bucket, Key: key }), { expiresIn: 600 });
  return c.json({ key, url });
});

app.get("/v1/blobs", async (c) => {
  const key = ownKey(await coupleOf(c), c.req.query("key"));
  const url = await getSignedUrl(s3, new GetObjectCommand({ Bucket: bucket, Key: key }), { expiresIn: 600 });
  return c.json({ key, url });
});

app.delete("/v1/blobs", async (c) => {
  const key = ownKey(await coupleOf(c), c.req.query("key"));
  await s3.send(new DeleteObjectCommand({ Bucket: bucket, Key: key }));
  return c.json({ ok: true });
});

export default app;
