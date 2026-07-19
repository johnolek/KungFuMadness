# Kung Fu Madness

Recreation of a lost early-2000s PBBG: async rock-paper-scissors kung fu. Players
send sealed challenges (3 rounds of attack + block heights committed up front),
opponents respond blind, fights resolve server-side with dice-roll damage, and
depth comes from scouting opponents' public match history.

## Stack

- **Rails 8.1**, Ruby **4.0.5** (see `.ruby-version`; default shell ruby differs,
  so prefix ad-hoc commands with `RBENV_VERSION=4.0.5` or rely on the rbenv shim).
- **PostgreSQL** — a single primary database serves the app, Solid Queue jobs,
  and Solid Cable broadcasts (no multi-database `connects_to`).
- **Solid Queue** (Active Job), **Solid Cable** (Action Cable). Both run on the
  primary DB; their tables are plain migrations in `db/migrate`. Solid Queue
  runs in-process via the Puma plugin when `SOLID_QUEUE_IN_PUMA` is set.
- **esbuild + esbuild-svelte** bundle **Svelte 5** islands over ERB/Turbo.
  **sass** owns the global retro theme.
- **RSpec** + factory_bot + faker + shoulda-matchers.
- Deploy target: **Coolify** (Dockerfile-based; wired up in a later phase).

## Dev workflow

- `bin/dev` — Rails server + `yarn watch:css` + `yarn watch:js` (no foreman).
  RubyMine users: run the server there with the watch scripts as a compound
  run configuration.
- `yarn build` — one-off minified JS bundle → `app/assets/builds/application.js`.
- `yarn build:css` — compile sass → `app/assets/builds/application.css`.
- `bundle exec rspec` — test suite.
- `bin/rails db:prepare` — create DBs + run migrations (incl. solid tables).

## Environment / configuration

Read from ENV (all optional in dev, which has sane fallbacks):

- `WEBAUTHN_RP_NAME` / `WEBAUTHN_RP_ID` / `WEBAUTHN_ORIGIN` — passkey relying-party
  config (dev falls back to `localhost` + ports 3000–3010).
- `MAIL_FROM` — sender address; also the Web Push VAPID subject (`mailto:`).
- `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` — Web Push keys. In dev, if unset, a
  keypair is generated on first boot and persisted to `tmp/vapid.json`
  (git-ignored) so push works with zero setup. Generate a production pair with
  `bin/rails push:generate_vapid`. Config lives in `config/initializers/web_push.rb`
  (the `Push` module: `Push.configured?`, `Push.public_key`, `Push.vapid_details`).

## PWA push notifications

Opt-in system push when a challenge lands. Flow: the dojo renders a "Challenge
alerts" panel + a `vapid-public-key` meta tag (verified fighters only, gated on
`Push.configured?`); `app/javascript/push.js` registers the service worker
(`/service-worker`, served by `rails/pwa`), subscribes via the Push API, and
POST/DELETEs `PushSubscription`s (unique by endpoint, one row per browser). On a
new challenge `Fight#broadcast_challenge_received` enqueues
`PushChallengeNotificationJob` for human opponents (never bots); the job fans out
to each subscription via `PushSubscription#deliver`, which prunes gone (404/410)
subscriptions. The service worker's `push` / `notificationclick` handlers show
the notification and focus/open the dojo. iOS requires add-to-home-screen.

## Bot ecology (the living population)

~200 bots behave like real people through a per-minute decision tick. They are
seeded by `Bots::Roster.generate` (a deterministic population pyramid of
kung-fu-movie names across belts 0–17, brains scaling with belt, personas with
spread-out activity windows) and persisted idempotently by `db/seeds.rb`.
PepsiDad stays the lone 9th dan.

**Personas** (`Bots::Persona`) interpret the `persona` section of a bot's
`strategy` jsonb — pure policy, no state, RNG-injectable:

- `activity` — UTC hour ranges the bot tends to be online (windows may wrap
  midnight); `active_now?` reads the hour in UTC.
- `session_chance` — P(log in) per active-hour tick while offline.
- `session_minutes` — session-length band; sets per-tick logout odds so sessions
  are geometric with that mean.
- `aggression` — P(issue a challenge) per online tick.
- `decline_style` — `meek` (ducks 3+ belts up + farmers), `proud` (snubs 3+ belts
  down + all farmers), `grudging` (only sometimes declines outright farming).
- `response_delay_minutes` — how long a challenge sits before an answer (coin-flip
  inside the band so responses spread out).

**The tick** (`Bots::TickJob`, every minute via `config/recurring.yml`) is fully
driven by an injectable `now`/`rng`, so the sim and specs replay it anywhere on
the timeline. Each tick, in order: (1) **presence** — offline bots in an active
hour may start a session (stamp `last_seen_at`, broadcast online via the same
`DojoChannel` path humans use); online bots may end one (go stale, broadcast
offline). (2) **respond** — online bots answer pending challenges older than their
delay, accepting via `Bots::Brain` or declining per temperament. (3) **challenge**
— per aggression, an online bot picks an online-ish fighter within ±2 belts and
challenges it, respecting the 5-min pair cooldown, the single-outstanding rule,
and a cap of 2 pendings stacked on any one human. Batched queries throughout (no
N+1 over 200 bots). Most bots most ticks do nothing.

Persona math with defaults (session_chance ≈ 0.04, mean session ≈ 30 min →
logout ≈ 0.033/tick, aggression ≈ 0.02): among bots whose activity window covers
the current hour, steady-state online fraction ≈ 0.04/(0.04+0.033) ≈ 0.55. With
~1/3 of the roster active in a given hour, ~36 of 200 are online; at aggression
0.02 that's ~0.7 challenges/minute initiated, roughly half of which clear
matchmaking — so the dojo settles a fight every few minutes, not a flood.

**Dev vs production cadence.** In production the tick is the only cadence: bots
answer only while online. In dev, `config.x.bots.immediate_response = true` also
enqueues `Bots::RespondJob` a few seconds after a human issues a challenge, so the
loop feels alive without a running scheduler. Run ticks manually with
`bin/rails bots:tick`; run the whole recurring set in dev with
`SOLID_QUEUE_IN_PUMA=1 bin/dev`.

**Progression risk (live).** Demotion hysteresis and the Tofu belt fire through
real `Fight#resolve!`. `RustDecayJob` (daily) bleeds 1%/day off idle fighters
above the blue floor (14+ days without a resolved fight), never past Blue.
`ExpireChallengesJob` (daily) flips pending challenges past `expires_at` to
expired and toasts the challenger. Any settled belt change — fight or rust —
broadcasts a `belt_change` promotion/demotion line to the dojo ticker via
`Fighter`'s own commit callback.

**Ecology sim (the balance authority).** `bin/rails balance:ecology` runs the same
tick loop in memory against `Bots::Roster` fighters — seeded RNG, no DB / jobs /
cable, fights resolve straight through `FightResolver` + `Xp::Rules` — until N
fights settle. Per-fighter starting XP is seeded from a STABLE name hash
(`Zlib.crc32`), not `String#hash` (which Ruby randomizes per process and would
make a "seeded" run drift between processes) (`N=`, `BOTS=`, `SEED=` to tune), then reports belt distribution
before/after, per-tier XP percentiles, promotion/demotion churn, and the Tofu
population. The `Ecology` spec asserts the population doesn't collapse (no belt
>40%, both promotions and demotions occur, Tofu <10%, belts 1–9 inhabited) at a
small seeded scale. Pairs with `balance:simulate` (combat win-rate envelope) as
the two tuning authorities.

## Islands convention

Rails owns routes and rendering (Turbo). Interactivity is Svelte 5 islands:
an element with `data-svelte-component="Name"` and `data-props="<json>"` mounts
the registered component with those props. Registration lives in
`app/javascript/islands.js`; mounting/unmounting is wired to `turbo:load` /
`turbo:before-cache`. Server flash reaches the `Toasts` island via
`toast_props(flash)` in the layout; any island can raise one client-side with
`document.dispatchEvent(new CustomEvent("toast", { detail: { type, message } }))`.

**Deviation from the project-tracker baseline:** Svelte `<style>` blocks ARE
allowed here. `build.mjs` uses `css: "injected"`, so component styles ship in
the bundle and mount at runtime. Global/shared retro styling still belongs in
sass (`app/assets/stylesheets/application.sass.scss`); component-local styling
belongs in the component's `<style>` block.

`app/javascript/components/DojoPlaceholder.svelte` is a proof island mounted on
the root page — it exercises the full ERB → island → props → `<style>` pipeline.

## Scouting, leaderboard & playback flavor

**`Scouting`** (`app/models/scouting.rb`) is a plain-Ruby read model over a
fighter's RESOLVED history (never pending/sealed moves). It exposes attack/block
height `Distribution`s (overall, a last-10 split, and per round 1–3), KO rate,
average fight length, win rate bucketed by opponent belt gap (`Rate` by
higher/same/lower), a newest-first `recent_form` W/L/D list, and `#streak`.
`#strip_summary` is the compact JSON the challenge modal and the no-JS scouting
partial read. It powers the profile "Scouting report" panel
(`fighters/_tendencies`, static CSS bar meters via the `tendency_meter` helper)
and the form strip on profiles.

**Leaderboard** — `GET /leaderboard` (`LeaderboardController`, navbar link) shows
top-25 all-time XP and most-active-this-week (resolved fights in the last 7 days),
humans and bots together. Verified fighters only, like the roster.

**Announcer flavor** — `Fight#playback_payload` now carries a deterministic,
replay-stable announcer `line` per round (`FightAnnouncer`, chosen by fight id +
round from a small pool — mutual block / thunderous roll / traded / one lands /
KO), plus a per-side `belt_change` callout (promotion/demotion) derived from the
snapshot belt + XP + delta. `FightPlayback.svelte` renders both; no animation.

**Footer** — the retro "visitor counter" is the real all-time resolved-fight
count (`resolved_fight_tally` helper, `Rails.cache` 5-min, zero-padded), beside
two pure-CSS 88×31 badges.

**Fonts** — still the monospace fallback stack; no open pixel display font is
present on the system or vendored, so the `--kfm-font-display` TODO stands (no
network fetch allowed).

---

## Game rules (canonical)

- Fight = 3 rounds. Per round each player commits: attack (height ∈ low/mid/high
  + style ∈ kick/punch) AND block height ∈ low/mid/high.
- Both attacks resolve simultaneously: an attack deals damage unless the
  defender's block height matches the attack height. Style doesn't affect
  resolution (yet) — it is ~99% aesthetic, stored for flavor/playback and future
  differentiation.
- Damage per landed hit = belt base + dice roll (starting point:
  `base(belt) + 1d8` where `base(belt) = 16 + 2 × belt_index`; the sim tunes it).
- KO when HP < 1 (double-KO same round = draw). After round 3, higher raw HP
  wins; equal = draw.
- `HP(belt) = 50 + 6 × belt_index`.
- Stats come from the fighter's **snapshot** belt (see snapshots).
- **Win condition tuning target:** 1–2 belts higher wins ~60–70% vs equal skill;
  KO plausible.

### Belts

Index 0 = **Tofu Belt** (joke sub-white; rename is one constant), 1 = white,
then yellow, orange, green, blue, purple, brown, red, 9 = black, 10+ = black dans.

### XP rules (module `Xp::Rules`, all constants in one tunable place)

- Win vs same belt: **+100**. Opponent above you: ×(1 + 0.5·gap), cap ×3. Below
  you: ×(1 − 0.35·gap), floor ×0.05.
- Loss vs same belt: **−50**. Vs higher: −max(10, 50 − 20·gap). Vs lower:
  −(50 + 40·gap) — the risk in accepting challenges from below.
- Draw: each side gets 30% of what they'd have gotten from the *other* outcome
  favoring them — underdog gains 30% of their would-be win XP (a white belt
  drawing a black belt gets real points), favorite loses 30% of their would-be
  loss. Same belt: +10 each.
- Challenge cooldown: cannot challenge the same opponent within 5 minutes of the
  previous fight/challenge between the pair (config constant). No XP decay math.
- Belt thresholds: white 0, yellow 300, orange 800, green 1500, blue 2500,
  purple 4000, brown 6000, red 8500, black 12000, +6000/dan. (The bot-ecology
  sim is the tuning authority.)
- Promotion: xp ≥ next threshold. Demotion hysteresis: only when xp < current
  threshold minus 20% of the span down one belt.
- Tofu Belt: xp < 0, floor −200, losses there cost 0, any win/draw sets xp to
  ≥ 0 → instant white. Joke, not a trap.
- Rust (LATER PHASE): brown+ with no resolved fight in 14 days lose 1% xp/day;
  **floor: can never demote below blue**. Declining doesn't reset the clock.

### Snapshots (critical)

BOTH fighters' belt/XP/stats are locked at challenge creation. A challenge sent
to a white belt is fought at white-belt stats even if they respond as a blue
belt; XP is computed from the snapshots. (Future) item selection still happens
at response time.

### Sealed-moves secrecy (critical)

The challenger's committed moves exist from creation but must never reach the
opponent pre-resolution. All fight output goes through explicit payload methods
(inbox payload = no moves; playback payload = only when resolved). A request
spec must assert the respond page + JSON contain zero challenger-move data.

---

Full design, data model, bot ecology, and phase breakdown live in the approved
plan: `~/.claude/plans/fuzzy-yawning-peacock.md`. This scaffold is **Phase 0**;
game models, auth, and the domain core start in Phase 1.

## Coding standards

- Avoid verbose descriptive comments; prefer self-documenting code. Comment only
  to explain something the code cannot.
- Ruby: prefer keyword arguments unless a method obviously takes one clear param.
  Add YARD docs where they help RubyMine navigate.
