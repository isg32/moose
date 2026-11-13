import { defineConfig } from "@neon/config/v1";

// Moose's backend on Neon: Postgres (pairing and sealed mail), Managed Auth
// (hidden per-phone accounts), the `api` Function, Realtime (live mail)
// and a private bucket for sealed media.
export default defineConfig({
  preview: {
    realtime: true,
  },
  auth: true,
  functions: {
    api: {
      name: "Moose API",
      source: "./src/api.ts",
      env: {
        // Realtime's URL and secret are not injected into Functions, so pass
        // them under names outside the reserved NEON_ prefix.
        REALTIME_URL: { value: process.env.NEON_REALTIME_URL, required: true },
        REALTIME_SECRET: { value: process.env.NEON_REALTIME_SECRET, required: true },
        MOOSE_BUCKET: "assets",
        // Firebase service account (base64 of backend/firebase-sa.json), set
        // by `npm run deploy` when the file is there. Without it, no push.
        FIREBASE_SA_B64: { value: process.env.FIREBASE_SA_B64, required: false },
      },
    },
  },
  buckets: {
    assets: { access: "private" },
  },
  branch: (branch) => {
    if (branch.isDefault) return {};
    if (!branch.exists) return { ttl: "7d" };
    return {};
  },
});
