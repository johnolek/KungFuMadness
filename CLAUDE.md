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
