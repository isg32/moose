// Deletes the accounts end-to-end runs leave (hidden emails e2e-…@moose.app
// from the app's live test) and everything they own.
import pg from "pg";

const db = new pg.Client({ connectionString: process.env.DATABASE_URL_UNPOOLED });
await db.connect();
const { rows } = await db.query<{ id: string }>(
  `select id::text from neon_auth."user" where email like 'e2e-%@moose.app'`,
);
const ids = rows.map((r) => r.id);
await db.query("delete from couples where id in (select couple_id from members where user_id = any($1))", [ids]);
await db.query("delete from members where user_id = any($1)", [ids]);
await db.query(`delete from neon_auth."user" where id::text = any($1)`, [ids]);
console.log(`deleted ${ids.length} e2e accounts`);
await db.end();
