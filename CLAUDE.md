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
  runs in-process via the Puma plugin when `SOLID_QUEUE_IN_PUMA` is set. Cable uses
  the DB-backed `solid_cable` adapter in BOTH dev and production (not `async`):
  since jobs run in forked Puma workers, an in-process adapter would strand
  worker-side broadcasts from the web process. `solid_cable` relays through the DB,
  so a broadcast from any process reaches every subscribed browser (dev polls at
  0.1s, 1h retention; prod 0.1s, 1d).
- **esbuild + esbuild-svelte** bundle **Svelte 5** islands over ERB/Turbo.
  **sass** owns the global retro theme.
- **RSpec** + factory_bot + faker + shoulda-matchers.
- Deploy target: **Coolify** (Dockerfile-based; wired up in a later phase).

## Dev workflow

- `bin/dev` — Rails server + `yarn watch:css` + `yarn watch:js` (no foreman).
  It exports `SOLID_QUEUE_IN_PUMA=1`, so Solid Queue (supervisor/dispatcher/
  scheduler) runs in-process and the bot world ticks automatically, exactly
  like production — no manual poking to keep the dojo alive. Dev now uses the
  `:solid_queue` Active Job adapter (test stays `:test`).
  RubyMine users: run the server there with the watch scripts as a compound
  run configuration, and set `SOLID_QUEUE_IN_PUMA=1` on it to get the same
  in-process bot cadence.
- `bin/rails bots:tick` — still available to fire a single tick by hand for
  manual poking; no longer required for the world to run.
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

**The tick — planner + jittered actors.** `Bots::TickJob` (every minute via
`config/recurring.yml`) is a PLANNER, not an actor. Driven by an injectable
`now`/`rng` (so the sim and specs replay it anywhere on the timeline), it consults
every bot's persona and decides what each WANTS this minute — (1) **presence**: an
offline bot in an active hour may want to start a session, an online bot may want
to end one; (2) **respond**: which pending challenges past the bot's delay are
ready to answer; (3) **challenge**: per aggression, whether an online bot wants to
go looking for a fight — then enqueues one `Bots::ActJob.set(wait:
rand(0..59).seconds).perform_later(bot_id, hints…)` per acting bot. Spreading the
work is the point: with ~20–40 acting bots a minute the world dribbles continuously
instead of firing every action at :00, and presence lands at the jittered second
too so the Online Now sidebar dribbles as well.

`Bots::ActJob` is the actor, run at its jittered second. Because up to a minute has
passed since the plan, it RE-EVALUATES against current state: it applies the
presence change only if still warranted (no duplicate online/offline broadcast),
answers each flagged challenge only if it's still pending (skipping any that
resolved or expired in the interim), and picks a live challenge target NOW, so the
±2-belt reach, 5-min pair cooldown, single-outstanding rule, and 2-pending cap on
any human are all enforced against fresh counts. It leans on the same locked,
pending-guarded paths (`Fight#respond!`, `#decline!`, `Fight.create_challenge!`),
so a duplicate or stale ActJob is a clean no-op — no distributed lock needed. The
durable delay is Solid Queue's, not in-memory scheduling, so the jitter survives
restarts and works across the forked Puma workers. Only that per-bot wait uses
`Kernel#rand`; the persona rolls stay on the injectable `rng`. Batched queries in
the planner (roster + pending challenges load once), so planning stays flat over
200 bots. Most bots most minutes want nothing and get no job. `bin/rails bots:tick`
runs the planner with `inline: true`, executing each ActJob in-process immediately
for manual dev poking.

Persona math with defaults (session_chance ≈ 0.04, mean session ≈ 30 min →
logout ≈ 0.033/tick, aggression ≈ 0.02): among bots whose activity window covers
the current hour, steady-state online fraction ≈ 0.04/(0.04+0.033) ≈ 0.55. With
~1/3 of the roster active in a given hour, ~36 of 200 are online; at aggression
0.02 that's ~0.7 challenges/minute initiated, roughly half of which clear
matchmaking — so the dojo settles a fight every few minutes, not a flood.

**Dev vs production cadence.** Dev runs the tick exactly like production: `bin/dev`
sets `SOLID_QUEUE_IN_PUMA=1`, dev uses the `:solid_queue` adapter, and
`config/recurring.yml` schedules `bots_tick` every minute in both environments — so
the planner fires each minute and the resulting `Bots::ActJob`s execute (in forked
workers) at their jittered seconds, with no running-scheduler caveat. On top of
that, dev-only `config.x.bots.immediate_response = true` still enqueues
`Bots::RespondJob` a few seconds after a human directly challenges a specific bot,
so a developer testing the challenge flow gets a fast reply instead of waiting out
that bot's `response_delay` window (orthogonal to the world cadence; off in prod).
Run a single tick by hand with `bin/rails bots:tick` (planner + inline ActJobs).

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
fighter's RESOLVED history (never pending/sealed moves). It still computes
distributions/KO rate/win-rate buckets and `#strip_summary`, but the UI
deliberately shows NONE of that anymore: scouting surfaces are raw match-history
tables only (challenge modal, challenge pages, other fighters' profiles) — the
player reads patterns themselves. To make that read possible at a glance, every
history table carries a Moves column of per-round attack+block glyphs for the
fighter whose history it is: `Fight#scouting_moves_for(fighter)` returns
key-free `[attack_height, attack_style, block_height]` tuples (EMPTY until
resolved, so payloads never carry sealed-move vocabulary), rendered by the
`move_icon`/`move_glyphs` ERB helpers (kept in sync with MoveIcon.svelte) and by
MoveIcon in the modal. The model's `recent_form`/`#streak` still power the
profile form strip. The old "Scouting report" tendency panel, the modal tendency
strip, and the `tendency_meter`/`win_rate_display` helpers are gone.

**Names ARE belts** — fighters everywhere render as a belt-colored chip whose
label is the name (`fighter_name_chip` / `fighter_name_link` helpers in ERB,
name-in-chip + `beltChipStyle` in Svelte). No separate belt columns/chips in
rosters, feeds, tables, inbox, or the modal.

**Leaderboard** — `GET /leaderboard` shows one board: top-25 all-time XP, humans
and bots together. (The most-active-this-week board was removed.)

**Match history home** — YOUR paginated history lives on the dojo homepage
(`DojoController`, `?page=`); your own profile shows none. Other fighters'
profiles keep theirs (that's the scouting surface).

**Playback** — `FightPlayback.svelte` renders a resolved fight as round panels
(3-up on desktop, scroll-snap carousel on mobile). Each panel is a 2-column grid
whose rows PAIR THE EXCHANGE: challenger's attack sits beside the block the
opponent answered it with, and vice versa below; centered HP after the round
(before → after in red when hit) closes each column. `MoveIcon.svelte` draws the
glyphs (stick figure + red strike marker / blue guard bar per height). No damage
prose; announcer lines exist in the payload but are not rendered. The
round-by-round reveal happens only the FIRST time a participant views their own
fight — `fights.challenger_seen_at` / `opponent_seen_at` are stamped by
`FightsController#claim_first_own_view`; spectators/repeats see everything. The
fight-settled toast is spoiler-free: "is settled" plus a "Watch the fight" link
(live.js → Toasts' `link` support), never the result.

**Move picker** — `MoveGrid.svelte` lays the three rounds out HORIZONTALLY
(columns), heights ordered low/mid/high, each an icon-button (MoveIcon) plus a
kick/punch toggle. Submit buttons are always labeled (Send challenge / Accept &
fight) and, while rounds are incomplete, disabled with a tippy.js tooltip (the
`tooltip` action in `app/javascript/tooltip.js`; retro `.tippy-box` styling in
sass — tippy's own CSS is not imported).

**Presence** — the Online Now sidebar shows online fighters AND recently offline
ones (within `Fighter::RECENT_OFFLINE_GRACE`, 5 min past the 2-min online
window) dimmed but still challengeable — they may have push on. Rows slide in
via svelte transitions; offline rows age out client-side on the server-supplied
`offline_expires_in`. A profile's challenge control mirrors the sidebar states
(open / Challenge sent disabled / Respond).

**Footer** — the retro "visitor counter" is the real all-time resolved-fight
count (`resolved_fight_tally` helper, `Rails.cache` 5-min, zero-padded), above a
classic under-construction gif (`app/assets/images/under-construction.gif`).

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
