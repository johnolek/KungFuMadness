<script>
  // Left sidebar: recent resolved fights, ONE line per fight — winner's name as a
  // belt-colored chip, loser dimmed, KO marker, relative time. The whole row
  // links to playback. Live: DojoChannel `fight_resolved` events (relayed as
  // `kfm:dojo`) prepend; belt_change events add promotion/demotion lines.
  // Rows the server masked (your own unwatched fight, spoilers hidden) render
  // both names neutral with a "?" badge; the live broadcast is public and
  // unmasked, so your own incoming rows are masked here client-side.
  import { beltChipStyle, beltVar, relativeTime } from "./belt.js"

  let { fights: initial = [], youId = null, hideSpoilers = false } = $props()

  const CAP = 20

  // svelte-ignore state_referenced_locally -- islands remount per visit; props seed state once
  let fights = $state(initial)

  // Re-derive relative labels on a slow tick so "just now" ages without churn.
  let now = $state(Date.now())

  function sides(fight) {
    if (fight.winner_side === "challenger") return { winner: fight.challenger, loser: fight.opponent }
    if (fight.winner_side === "opponent") return { winner: fight.opponent, loser: fight.challenger }
    return null
  }

  function maskOwn(fight) {
    const mine = fight.challenger?.id === youId || fight.opponent?.id === youId
    if (!hideSpoilers || !mine) return fight
    return {
      ...fight,
      masked: true, ko: null, draw: null, winner_side: null,
      challenger: { ...fight.challenger, moves: [], xp_delta: null },
      opponent: { ...fight.opponent, moves: [], xp_delta: null }
    }
  }

  $effect(() => {
    const handler = (event) => {
      const message = event.detail
      if (message?.event === "fight_resolved" && message.fight) {
        if (fights.some((f) => f.id === message.fight.id)) return
        fights = [maskOwn(message.fight), ...fights].slice(0, CAP)
      } else if (message?.event === "belt_change" && message.fighter) {
        const entry = {
          id: `belt-${message.fighter.id}-${Date.now()}`,
          kind: "belt_change",
          direction: message.direction,
          fighter: message.fighter,
          from_belt_name: message.from_belt_name
        }
        fights = [entry, ...fights].slice(0, CAP)
      }
    }
    document.addEventListener("kfm:dojo", handler)
    return () => document.removeEventListener("kfm:dojo", handler)
  })

  $effect(() => {
    const timer = setInterval(() => (now = Date.now()), 30000)
    return () => clearInterval(timer)
  })
</script>

<section class="panel-kfm sidebar-panel">
  <div class="panel-kfm-title">Recent fights</div>
  {#if fights.length === 0}
    <p class="empty">No fights settled yet.</p>
  {:else}
    <ul class="feed">
      {#each fights as fight (fight.id)}
        {#if fight.kind === "belt_change"}
          <li class="feed__row feed__row--belt feed__row--{fight.direction}">
            <a class="feed__link" href={fight.fighter.url}>
              <span class="feed__line">
                <span class="chip" style={beltChipStyle(fight.fighter.belt)}>{fight.fighter.display_name}</span>
                <span class="feed__vs">{fight.direction === "promotion" ? "rose to" : "fell to"} {fight.fighter.belt_name}</span>
              </span>
            </a>
          </li>
        {:else if fight.masked}
          <li class="feed__row">
            <a class="feed__link" href={fight.url}>
              <span class="feed__line">
                <span class="chip chip--draw" style={beltChipStyle(fight.challenger.belt)}>{fight.challenger.display_name}</span>
                <span class="badge badge--masked" title="You haven't watched this fight yet">?</span>
              </span>
              <span class="feed__line">
                <span class="chip chip--draw" style={beltChipStyle(fight.opponent.belt)}>{fight.opponent.display_name}</span>
                <span class="feed__time">{(now, relativeTime(fight.resolved_at))}</span>
              </span>
            </a>
          </li>
        {:else}
          {@const s = sides(fight)}
          <li class="feed__row" class:feed__row--draw={s === null}>
            <a class="feed__link" href={fight.url}>
              {#if s}
                <span class="feed__line">
                  <span class="chip" style={beltChipStyle(s.winner.belt)}>{s.winner.display_name}</span>
                  {#if fight.ko}<span class="badge badge--ko">KO</span>{/if}
                </span>
                <span class="feed__line">
                  <span class="chip chip--loser" style="border-left-color: {beltVar(s.loser.belt)};">{s.loser.display_name}</span>
                  <span class="feed__time">{(now, relativeTime(fight.resolved_at))}</span>
                </span>
              {:else}
                <span class="feed__line">
                  <span class="chip chip--draw" style={beltChipStyle(fight.challenger.belt)}>{fight.challenger.display_name}</span>
                  <span class="badge badge--draw">Draw</span>
                  {#if fight.ko}<span class="badge badge--ko">KO</span>{/if}
                </span>
                <span class="feed__line">
                  <span class="chip chip--draw" style={beltChipStyle(fight.opponent.belt)}>{fight.opponent.display_name}</span>
                  <span class="feed__time">{(now, relativeTime(fight.resolved_at))}</span>
                </span>
              {/if}
            </a>
          </li>
        {/if}
      {/each}
    </ul>
  {/if}
</section>

<style>
  .sidebar-panel { margin-bottom: 0; }

  .empty { color: var(--kfm-ink-soft); font-size: 0.85rem; }

  .feed { list-style: none; margin: 0; padding: 0; }

  .feed__row {
    border-bottom: 1px dashed var(--kfm-ink-soft);
  }
  .feed__row:last-child { border-bottom: none; }

  .feed__link {
    display: flex;
    flex-direction: column;
    gap: 0.1rem;
    padding: 0.3rem 0;
    text-decoration: none;
    color: var(--kfm-ink);
    font-size: 0.78rem;
    line-height: 1.3;
  }
  .feed__link:hover { background: rgba(0, 0, 0, 0.04); }

  .feed__line {
    display: flex;
    align-items: center;
    gap: 0.3rem;
    min-width: 0;
    white-space: nowrap;
  }

  .chip {
    display: inline-block;
    padding: 0 0.3rem;
    border: 1px solid var(--kfm-border);
    font-size: 0.7rem;
    font-weight: bold;
    text-transform: uppercase;
    overflow: hidden;
    text-overflow: ellipsis;
    flex: 0 1 auto;
    min-width: 0;
  }

  .chip--draw { opacity: 0.75; }

  /* The loser keeps their belt color, but as a quiet accent bar instead of the
     winner's solid fill — names in both lines start at the same x. */
  .chip--loser {
    background: transparent;
    color: var(--kfm-ink-soft);
    font-weight: normal;
    border-left-width: 4px;
    border-left-style: solid;
  }

  .badge {
    flex: none;
    display: inline-block;
    padding: 0 0.25rem;
    font-size: 0.58rem;
    font-weight: bold;
    text-transform: uppercase;
    border: 1px solid var(--kfm-border);
  }
  .badge--ko { background: var(--kfm-belt-red); color: var(--kfm-parchment); }
  .badge--draw { background: var(--kfm-tatami); color: var(--kfm-ink); }
  .badge--masked { background: var(--kfm-ink); color: var(--kfm-parchment); }

  .feed__time {
    color: var(--kfm-ink-soft);
    font-size: 0.65rem;
    margin-left: auto;
    flex: none;
  }

  .feed__row--belt { border-left: 3px solid var(--kfm-belt-yellow); }
  .feed__row--belt .feed__link { padding-left: 0.3rem; font-style: italic; }
  .feed__row--promotion { border-left-color: var(--kfm-belt-green); }
  .feed__row--demotion { border-left-color: var(--kfm-belt-red); }
</style>
