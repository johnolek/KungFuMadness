# Deploying Kung Fu Madness to Coolify

This app deploys as a **single Dockerfile-built container** plus **one PostgreSQL
resource**. Postgres is the only stateful dependency — it serves the app, Solid
Queue (jobs + the per-minute bot tick), and Solid Cable (live dojo broadcasts).
There is **no Redis, no separate worker, and no persistent file volume** (the app
has no Active Storage attachments — all state is in Postgres).

Solid Queue runs *inside* Puma (`SOLID_QUEUE_IN_PUMA=1`, baked into the image), so
a single web container also runs the job workers, the dispatcher, and the
recurring scheduler that fires `Bots::TickJob` every minute. No second service.

---

## 1. Create the PostgreSQL resource

In your Coolify project: **+ New Resource → Database → PostgreSQL** (16 or newer).

- Note the connection string Coolify generates. Use the **internal** URL (the one
  on Coolify's private network, e.g. `postgres://user:pass@<service>:5432/dbname`)
  as `DATABASE_URL` for the app. Do not expose Postgres publicly.
- The app runs `db:prepare` on every boot, so it creates the schema and runs all
  migrations (including the Solid Queue / Solid Cable tables) automatically on the
  first deploy. You do **not** need to run migrations by hand.

## 2. Create the application

**+ New Resource → Application → Public/Private Git Repository**, pointing at this
repo.

- **Build Pack: Dockerfile** (Coolify builds the repo's `Dockerfile`; do not pick
  Nixpacks). The Dockerfile compiles JS (esbuild + Svelte) and CSS (dart-sass)
  during `assets:precompile` in a build stage, then ships a slim image with no
  Node and no `node_modules`.
- **Port: 3000** (the image `EXPOSE`s 3000 and Puma listens there).
- Coolify passes the build arg `SOURCE_COMMIT`; the Dockerfile writes it to
  `REVISION` so the running app knows its deployed commit.
- Set a domain (see §5) before the first deploy if you can — the passkey config
  (`WEBAUTHN_*`) must match the final HTTPS origin.

## 3. Environment variables

Set these on the **application** resource. "Req?" = required for a healthy deploy.

| Variable | Req? | Example | Purpose |
|---|---|---|---|
| `DATABASE_URL` | **Yes** | `postgres://kfm:secret@kfm-db:5432/kfm` | Postgres connection (app + jobs + cable). Use the internal Coolify URL. |
| `RAILS_MASTER_KEY` | **Yes** | `<contents of config/master.key>` | Decrypts `config/credentials.yml.enc` and provides `secret_key_base`. This repo commits `credentials.yml.enc`; `master.key` is git-ignored, so supply it here. (Alternatively set `SECRET_KEY_BASE` instead — see note below.) |
| `WEBAUTHN_RP_ID` | **Yes** | `kungfumadness.com` | Passkey Relying Party ID = the registrable domain (host only, no scheme/port). Passkeys are bound to this; getting it wrong makes existing passkeys unusable. |
| `WEBAUTHN_ORIGIN` | **Yes** | `https://kungfumadness.com` | Exact browser origin (scheme + host, include port only if non-standard). Must be the real HTTPS URL. Also the fallback source for the mailer host. |
| `WEBAUTHN_RP_NAME` | No | `Kung Fu Madness` | Human-readable name shown in the passkey prompt. Defaults to `Kung Fu Madness`. |
| `MAIL_FROM` | **Yes** | `dojo@kungfumadness.com` | Sender for the magic-link sign-in email; also the Web Push VAPID `mailto:` subject. Without it mail sends from `dojo@localhost`. |
| `MAIL_HOST` | No | `kungfumadness.com` | Host used to build the magic-link URL in emails. If unset, derived from `WEBAUTHN_ORIGIN`'s host, else `localhost`. Usually leave unset. |
| `SMTP2GO_API_KEY` | **Yes\*** | `api-XXXXXXXX...` | **Preferred email path.** Sends via the SMTP2GO HTTP API (`Smtp2goDelivery`) over HTTPS/443 with an explicit logged result per message. When set, all `SMTP_*` vars are ignored. \*Email is required for sign-in; set either this or the `SMTP_*` block. |
| `SMTP_ADDRESS` | **Yes\*** | `smtp.postmarkapp.com` | SMTP server — the fallback path when `SMTP2GO_API_KEY` is not set. |
| `SMTP_PORT` | No | `587` | SMTP port. Default `587` (STARTTLS). |
| `SMTP_USERNAME` | **Yes\*** | `apikey` / account user | SMTP auth user (fallback path). |
| `SMTP_PASSWORD` | **Yes\*** | `<smtp password/token>` | SMTP auth password/token (fallback path). |
| `SMTP_AUTHENTICATION` | No | `plain` | `plain`, `login`, or `cram_md5`. Default `plain`. |
| `SMTP_DOMAIN` | No | `kungfumadness.com` | HELO domain some providers require. |
| `VAPID_PUBLIC_KEY` | No | `BJ...` (base64url) | Web Push public key. Without the pair, the opt-in push UI hides itself and everything else still works. Generate with `bin/rails push:generate_vapid`. |
| `VAPID_PRIVATE_KEY` | No | `x1...` (base64url) | Web Push private key (from the same `push:generate_vapid` run). |
| `WEB_CONCURRENCY` | No (baked `2`) | `2` | Puma worker processes. Override for a bigger box. |
| `JOB_CONCURRENCY` | No (default `1`) | `1` | Solid Queue worker processes (each runs 3 threads). Bump if job volume grows. |
| `RAILS_MAX_THREADS` | No (default `3`) | `3` | Puma threads per worker. |
| `SOLID_QUEUE_IN_PUMA` | No (baked `1`) | `1` | Runs jobs + recurring scheduler in Puma. **Leave baked**; do not set to empty or the bot tick / daily jobs stop running. |
| `RAILS_LOG_LEVEL` | No | `info` | Log verbosity. Default `info`. |

\* Email is functionally required: the **only** way to sign in is the emailed magic
link. If neither `SMTP2GO_API_KEY` nor the `SMTP_*` vars are set the app still
boots and passes health checks, but nobody can log in.

### Email via SMTP2GO (recommended)

Set **one** env var and you're done:

1. In SMTP2GO's dashboard, create an API key (Settings → API Keys) and **verify
   your sender** — either the `MAIL_FROM` address or its domain (Sending →
   Verified Senders). SMTP2GO rejects sends from unverified senders.
2. Set `SMTP2GO_API_KEY` on the app resource (runtime is enough; buildtime not
   needed) and make sure `MAIL_FROM` is the verified sender.
3. Redeploy. Every send now logs an explicit result:
   `[smtp2go] delivered "Your sign-in link" to … email_id=…` on success, or
   `[smtp2go] delivery FAILED (HTTP 4xx) …` with the provider's reason on
   failure — so a bad key or unverified sender is visible in the container logs
   instead of vanishing into SMTP.

No ports, TLS negotiation, or SMTP credentials involved — it's a JSON POST to
`api.smtp2go.com` over 443. The plain-SMTP config remains as a fallback for any
other provider: it applies only when `SMTP2GO_API_KEY` is absent.

**`RAILS_MASTER_KEY` vs `SECRET_KEY_BASE`.** This repo commits an encrypted
`config/credentials.yml.enc`, so the recommended path is to set `RAILS_MASTER_KEY`
(the contents of your local `config/master.key`). If you would rather not ship the
master key, set `SECRET_KEY_BASE` to a random 128-hex string (`bin/rails secret`)
instead — nothing in the app currently reads a credential out of
`credentials.yml.enc` at runtime, so either works. Pick one.

## 4. First deploy → one-off bootstrap (brains)

Deploy. On boot the container runs `db:prepare` (schema + migrations) and starts
Puma with Solid Queue in-process. `/up` should go green within ~20s.

**The ~200-bot roster seeds itself automatically.** `db:prepare` runs `db/seeds.rb`
when it first creates the database, so the full belt pyramid (Tofu → 9th-dan
PepsiDad) is populated on the first deploy with no manual step. The recurring
scheduler starts ticking `Bots::TickJob` every minute immediately, so the world is
alive out of the box.

What is **not** seeded automatically is the trained neural-net bot brains. Bots are
fully playable without them — `Bots::Brain` falls back to weighted-random
("biased") move sampling when the `brains` table is empty — so this is polish, not
a hard dependency. To give the bots real scouting-based best-response, run this
one-off command once, in Coolify's **Terminal / Execute Command** for the app:

```bash
bin/rails kfm:bootstrap
```

It is **idempotent and safe to re-run**. It:

1. Seeds the roster if it's somehow sparse (fewer than 150 bots) — a no-op safety
   net, since `db:prepare` already seeded it.
2. Trains the NN brains **once** (only if the `brains` table is empty), with modest
   settings (`FIGHTS=1500 BOTS=80 EPOCHS=20`) that finish in ~25s.

**Why a one-off and not baked into boot?** Training takes real time and we want
boot (and the health check) to stay fast, and we don't want every redeploy to
retrain. If you want a sharper net, pass the same knobs `bots:train` accepts, e.g.
`FIGHTS=5000 EPOCHS=40 bin/rails kfm:bootstrap`, or run the full-quality trainer
later with `bin/rails bots:train` (it just adds a new brain version, picked up on
the next cache clear / boot).

Once bootstrapped, the recurring scheduler (running inside Puma) drives the world:
`Bots::TickJob` every minute (logins/logouts, bot challenges and responses),
`RustDecayJob` daily at 4:00, `ExpireChallengesJob` daily at 4:05.

### Generating VAPID keys (optional, for push notifications)

Push notifications are opt-in and the app runs fine without them. To enable them,
generate a keypair **once** and set both values as env vars, then redeploy:

```bash
bin/rails push:generate_vapid
# prints:
#   VAPID_PUBLIC_KEY=...
#   VAPID_PRIVATE_KEY=...
```

Run it locally or in the container terminal; copy the two lines into the app's env
vars. Keep the pair stable — regenerating invalidates existing browser
subscriptions.

## 5. Domain, SSL, and the reverse proxy

- Point your domain at the app in Coolify and let Coolify provision Let's Encrypt
  TLS. Coolify's proxy (Traefik) terminates SSL and forwards plain HTTP to the
  container on port 3000.
- `production.rb` sets `config.assume_ssl = true` and `config.force_ssl = true`,
  which is exactly right behind an SSL-terminating proxy: Rails trusts the
  `X-Forwarded-Proto` header, issues secure cookies, and sends HSTS.
- **`WEBAUTHN_ORIGIN` / `WEBAUTHN_RP_ID` must match the final HTTPS domain** before
  anyone registers a passkey. `WEBAUTHN_ORIGIN=https://<domain>`,
  `WEBAUTHN_RP_ID=<domain>` (host only). A mismatch makes passkey registration and
  login fail in the browser with an opaque error.
- The health check path is **`/up`** (returns 200 when the app boots cleanly). The
  Dockerfile already declares a `HEALTHCHECK` against it; you can also point
  Coolify's health check at `/up`.

## 6. Post-deploy smoke checklist

- [ ] `/up` returns 200 (green in Coolify).
- [ ] The landing page and `GET /sign-up` render with styling (CSS/JS assets load
      — confirms `assets:precompile` shipped in the image).
- [ ] Logs show Solid Queue starting inside Puma and the scheduler scheduling
      recurring tasks (grep the container logs for `SolidQueue` / `scheduling` /
      `bots_tick`).
- [ ] The leaderboard (`/leaderboard`) and dojo show bots (seeded automatically on
      first boot); within a minute or two you see bot activity (online/offline,
      challenges). Running `kfm:bootstrap` adds trained brains on top.
- [ ] **Sign up** with your email → you receive the magic-link email → clicking it
      logs you in. (This exercises SMTP end-to-end; if no email arrives, fix
      `SMTP_*` and check logs.)
- [ ] **Register a passkey** from settings and sign in with it. If the browser
      rejects it, your `WEBAUTHN_RP_ID` / `WEBAUTHN_ORIGIN` don't match the domain.
- [ ] (Optional) With VAPID keys set, the "Challenge alerts" opt-in appears for a
      verified fighter and a subscription registers without console errors.

## 7. Redeploys

Just push to the deployed branch (or trigger a redeploy). Each deploy rebuilds the
image, runs `db:prepare` (new migrations apply automatically), and restarts. The
roster and brains persist in Postgres; `kfm:bootstrap` is a no-op on a populated
database, so you never need to re-run it.

## 8. Troubleshooting

**`ArgumentError: key must be 16 bytes` at boot (`cipher.key = @secret`),
container unhealthy, deploy rolls back.** The `RAILS_MASTER_KEY` value the
container received is the wrong *length* — it must be **exactly the 32 hex
characters** of your local `config/master.key`, nothing more. A trailing
newline, a leading/trailing space, surrounding quotes, or an incomplete paste
all produce this exact error (`db:prepare` dies before Puma starts, so `/up`
never answers). A key of the right length but the wrong *value* fails
differently (`ActiveSupport::MessageEncryptor::InvalidMessage`). Fix: in
Coolify, reveal the value (eye icon), delete the variable, and re-add it by
pasting the raw 32 characters — on macOS,
`cat config/master.key | pbcopy` copies it without a newline. Both "Available at
Buildtime" and "Available at Runtime" should be checked.

**Coolify warns the healthcheck needs curl/wget.** Informational only — this
image installs `curl` and declares its own `HEALTHCHECK` against `/up`. If the
container is reported unhealthy, the real cause is in the container logs (as
above), not the healthcheck mechanism.

**Jobs seem enqueued but nothing runs / no fights are happening.** Run the
one-command health snapshot in the app container (Coolify → Terminal):

```bash
bin/rails kfm:doctor
```

It prints the Solid Queue process registry (supervisor / dispatcher / worker /
scheduler + heartbeats), pending/finished/FAILED job counts, and the bot-world
activity numbers. How to read it:

- **No processes registered** → the supervisor isn't running inside Puma. The
  image bakes `SOLID_QUEUE_IN_PUMA=1`; grep the container logs for
  `Started Supervisor` / `Started Worker` and make sure nothing in Coolify
  overrides the start command or that env var.
- **Stale heartbeats or FAILED executions** → jobs are erroring; the doctor
  prints the last failure's error.
- **Everything healthy but 0 resolved fights** → almost certainly just the
  cold-start ramp. Bots trickle online a few per minute (steady state is only
  reached after ~15–30 minutes), only ~2% of online bots look for a fight each
  minute, and bots answer challenges only **while online**, after a 1–12 minute
  persona delay — so a challenge you send to an offline bot can legitimately sit
  for hours. Expect the first bot-vs-bot fights ~10–30 minutes after first boot,
  then roughly one every few minutes. (Dev feels faster only because
  `immediate_response` is on there.)

**Build fails on `SecretsUsedInArgOrEnv`.** Already handled: the Dockerfile's
check directive skips that single lint rule (the `RAILS_MASTER_KEY` build ARG is
the standard Rails/Coolify shape). If you see it, you're building a stale
commit.
