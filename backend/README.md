# Moose backend (Neon)

One Neon branch, declared in `neon.ts`:

| Service | Used for |
| --- | --- |
| Managed Auth | A hidden email/password account per phone; the app sends its 15-minute JWT to the API |
| Postgres | `couples`, `members` (name, X25519 public key), `invites`, `mailbox` (sealed envelopes, deleted on ack). Schema: `db/schema.sql` |
| Function `api` | `src/api.ts` (Hono): `/v1/me`, `/v1/invites`, `/v1/join`, `/v1/unpair`, `/v1/mail`, `/v1/mail/ack`, `/v1/blobs`, `/v1/live` |
| Realtime | `/v1/live` subscribes to the member's mailbox and pushes each new row over a WebSocket |
| Object storage | Private bucket `assets`; sealed media under `c/<couple>/<uuid>` through presigned URLs |

```bash
npx -y neon@latest env pull   # writes .env.local (git-ignored)
npm install
npm run build                 # type-check
npm run migrate               # apply db/schema.sql
npm run deploy                # neon deploy --env .env.local
npm test                      # end to end against the deployed branch
```

The server never sees plaintext: bodies and blobs are encrypted on the phone.
