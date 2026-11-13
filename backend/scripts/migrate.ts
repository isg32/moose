// Applies db/schema.sql to the branch in DATABASE_URL_UNPOOLED. Idempotent.
import { readFileSync } from "node:fs";
import pg from "pg";

const url = process.env.DATABASE_URL_UNPOOLED ?? process.env.DATABASE_URL;
if (!url) throw new Error("DATABASE_URL_UNPOOLED is not set (run neon env pull)");
const client = new pg.Client({ connectionString: url });
await client.connect();
await client.query(readFileSync(new URL("../db/schema.sql", import.meta.url), "utf8"));
const { rows } = await client.query(
  "select table_name from information_schema.tables where table_schema = 'public' order by 1",
);
console.log("schema ok:", rows.map((r) => r.table_name).join(", "));
await client.end();
