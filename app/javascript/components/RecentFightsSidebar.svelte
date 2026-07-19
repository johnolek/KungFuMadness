<script>
  // Left sidebar: recent resolved fights at a glance. Winner bold with belt chip,
  // loser dimmed, KO/draw badges, relative time, whole row links to playback.
  // Live: DojoChannel `fight_resolved` events (relayed as `kfm:dojo`) prepend.
  import { beltChipStyle, relativeTime } from "./belt.js"

  let { fights: initial = [] } = $props()

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

  $effect(() => {
    const handler = (event) => {
      const message = event.detail
      if (message?.event === "fight_resolved" && message.fight) {
        if (fights.some((f) => f.id === message.fight.id)) return
        fights = [message.fight, ...fights].slice(0, CAP)
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
              <span class="feed__belt">
                <span class="chip" style={beltChipStyle(fight.fighter.belt)}>{fight.fighter.belt_name}</span>
                <strong>{fight.fighter.display_name}</strong>
                {#if fight.direction === "promotion"}
                  reached {fight.fighter.belt_name} belt
                {:else}
                  fell to {fight.fighter.belt_name} belt
                {/if}
              </span>
            </a>
          </li>
        {:else}
        {@const s = sides(fight)}
        <li class="feed__row" class:feed__row--draw={s === null}>
          <a class="feed__link" href={fight.url}>
            {#if s}
              <span class="feed__winner">
                <span class="chip" style={beltChipStyle(s.winner.belt)}>{s.winner.belt_name}</span>
                <strong>{s.winner.display_name}</strong>
              </span>
              <span class="feed__vs">beat</span>
              <span class="feed__loser">{s.loser.display_name}</span>
            {:else}
              <span class="feed__winner"><strong>{fight.challenger.display_name}</strong></span>
              <span class="feed__vs">drew</span>
              <span class="feed__loser">{fight.opponent.display_name}</span>
            {/if}
            <span class="feed__meta">
              {#if fight.ko}<span class="badge badge--ko">KO</span>{/if}
              {#if s === null}<span class="badge badge--draw">draw</span>{/if}
              <span class="feed__time">{(now, relativeTime(fight.resolved_at))}</span>
            </span>
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
    display: block;
    padding: 0.4rem 0;
    text-decoration: none;
    color: var(--kfm-ink);
    font-size: 0.85rem;
    line-height: 1.35;
  }
  .feed__link:hover { color: var(--kfm-ink); background: rgba(0, 0, 0, 0.04); }

  .feed__winner .chip {
    display: inline-block;
    padding: 0 0.3rem;
    border: 1px solid var(--kfm-border);
    font-size: 0.65rem;
    font-weight: bold;
    text-transform: uppercase;
    vertical-align: middle;
  }

  .feed__vs {
    color: var(--kfm-ink-soft);
    font-style: italic;
    margin: 0 0.15rem;
  }

  .feed__loser { color: var(--kfm-ink-soft); }
  .feed__row--draw .feed__winner strong,
  .feed__row--draw .feed__loser { color: var(--kfm-ink-soft); font-weight: bold; }

  .feed__meta { display: block; margin-top: 0.1rem; }

  .badge {
    display: inline-block;
    padding: 0 0.3rem;
    font-size: 0.6rem;
    font-weight: bold;
    text-transform: uppercase;
    border: 1px solid var(--kfm-border);
    margin-right: 0.3rem;
  }
  .badge--ko { background: var(--kfm-belt-red); color: var(--kfm-parchment); }
  .badge--draw { background: var(--kfm-tatami); color: var(--kfm-ink); }

  .feed__time { color: var(--kfm-ink-soft); font-size: 0.7rem; }

  .feed__row--belt { border-left: 3px solid var(--kfm-belt-yellow); }
  .feed__row--belt .feed__link { padding-left: 0.4rem; font-style: italic; }
  .feed__row--promotion { border-left-color: var(--kfm-belt-green); }
  .feed__row--demotion { border-left-color: var(--kfm-belt-red); }
  .feed__belt .chip {
    display: inline-block;
    padding: 0 0.3rem;
    border: 1px solid var(--kfm-border);
    font-size: 0.65rem;
    font-weight: bold;
    text-transform: uppercase;
    vertical-align: middle;
    margin-right: 0.2rem;
  }
</style>
