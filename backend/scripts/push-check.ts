// Who has a push token, and whether a test wake-up reaches them.
// Usage: node --env-file=.env.local scripts/push-check.ts [send <name>]
// "send" pushes a plain "New message" wake-up (no message body) to <name>.
import { readFileSync } from "node:fs";
import pg from "pg";

process.env.FIREBASE_SA_B64 ??= Buffer.from(readFileSync("firebase-sa.json")).toString("base64");
const { push } = await import("../src/push.ts");

const db = new pg.Client({ connectionString: process.env.DATABASE_URL_UNPOOLED });
await db.connect();
const { rows } = await db.query(
  `select m.name, m.couple_id, m.fcm_token from members m
   where m.user_id not in (select id::text from neon_auth.users_sync where email like 'e2e-%')
   order by m.couple_id, m.name`,
).catch(async () => db.query(`select name, couple_id, fcm_token from members order by couple_id, name`));
for (const r of rows) {
  let line = `${r.name.padEnd(12)} couple ${String(r.couple_id).slice(0, 8)}  token ${r.fcm_token ? "yes" : "no"}`;
  if (process.argv[2] === "send" && r.name === process.argv[3] && r.fcm_token) {
    const id = crypto.randomUUID();
    line += `  test push: ${await push(r.fcm_token, { kind: "msg", id, sender: "test" })}`;
  }
  console.log(line);
}
await db.end();
