<script>
  // Right sidebar: fighters seen in the last 2 minutes. Each row links to the
  // profile and carries a challenge control whose shape depends on your standing
  // toward them — Challenge (open the modal), a dimmed "Challenged" marker when
  // you already have one out, or Respond when they're waiting on you.
  //
  // Live: DojoChannel presence events (relayed as `kfm:dojo`) add/remove rows;
  // your own actions and FighterChannel events flip a row's challenge state.
  import { beltChipStyle } from "./belt.js"

  let { fighters: initial = [], youId } = $props()

  // svelte-ignore state_referenced_locally -- islands remount per visit; props seed state once
  let fighters = $state(initial.filter((f) => f.id !== youId))

  function upsertPresence(fighter) {
    if (fighter.id === youId) return
    const existing = fighters.find((f) => f.id === fighter.id)
    if (existing) {
      Object.assign(existing, {
        name: fighter.name,
        display_name: fighter.display_name,
        belt: fighter.belt,
        belt_name: fighter.belt_name,
        url: fighter.url
      })
    } else {
      fighters = [...fighters, { ...fighter, challenge_state: "open", fight_id: null }]
    }
  }

  function removeFighter(id) {
    fighters = fighters.filter((f) => f.id !== id)
  }

  function setState(id, state, fightId = null) {
    const row = fighters.find((f) => f.id === id)
    if (row) {
      row.challenge_state = state
      row.fight_id = fightId
    }
  }

  $effect(() => {
    const onDojo = (event) => {
      const message = event.detail
      if (message?.event !== "presence" || !message.fighter) return
      if (message.online) upsertPresence(message.fighter)
      else removeFighter(message.fighter.id)
    }
    const onSent = (event) => setState(event.detail.opponentId, "challenged")
    const onFighter = (event) => {
      const message = event.detail
      const fight = message?.fight
      if (!fight) return
      if (message.event === "challenge_received") {
        // They now have a pending challenge waiting on you → offer Respond.
        setState(fight.challenger.id, "respond", fight.id)
      } else if (message.event === "challenge_resolved" || message.event === "challenge_declined") {
        // An outbound challenge of yours closed → the mat with them is clear again.
        setState(fight.opponent.id, "open")
      }
    }
    document.addEventListener("kfm:dojo", onDojo)
    document.addEventListener("kfm:challenge-sent", onSent)
    document.addEventListener("kfm:fighter", onFighter)
    return () => {
      document.removeEventListener("kfm:dojo", onDojo)
      document.removeEventListener("kfm:challenge-sent", onSent)
      document.removeEventListener("kfm:fighter", onFighter)
    }
  })
</script>

<section class="panel-kfm sidebar-panel">
  <div class="panel-kfm-title">Online now</div>
  {#if fighters.length === 0}
    <p class="empty">The dojo is quiet. No one else is on the mat.</p>
  {:else}
    <ul class="online">
      {#each fighters as fighter (fighter.id)}
        <li class="online__row">
          <a class="online__name" href={fighter.url}>
            <span class="chip" style={beltChipStyle(fighter.belt)}>{fighter.belt_name}</span>
            {fighter.display_name}
          </a>
          {#if fighter.challenge_state === "respond"}
            <button type="button" class="act act--respond" data-respond-open={fighter.fight_id}>Respond</button>
          {:else if fighter.challenge_state === "challenged"}
            <span class="act act--sent" title="Waiting on their answer">Challenged</span>
          {:else}
            <button type="button" class="act" data-challenge-open={fighter.id}>Challenge</button>
          {/if}
        </li>
      {/each}
    </ul>
  {/if}
</section>

<style>
  .sidebar-panel { margin-bottom: 0; }

  .empty { color: var(--kfm-ink-soft); font-size: 0.85rem; }

  .online { list-style: none; margin: 0; padding: 0; }

  .online__row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.5rem;
    padding: 0.35rem 0;
    border-bottom: 1px dashed var(--kfm-ink-soft);
  }
  .online__row:last-child { border-bottom: none; }

  .online__name {
    text-decoration: none;
    color: var(--kfm-ink);
    font-size: 0.85rem;
    font-weight: bold;
    min-width: 0;
    flex: 1 1 auto;
    overflow-wrap: anywhere;
  }
  .online__name:hover { color: var(--kfm-belt-red); }

  .chip {
    display: inline-block;
    padding: 0 0.3rem;
    border: 1px solid var(--kfm-border);
    font-size: 0.6rem;
    font-weight: bold;
    text-transform: uppercase;
    vertical-align: middle;
  }

  .act {
    flex: none;
    font-family: var(--kfm-font-display, "Courier New", monospace);
    font-weight: bold;
    text-transform: uppercase;
    font-size: 0.65rem;
    letter-spacing: 0.05em;
    padding: 0.2rem 0.5rem;
    color: var(--kfm-ink);
    background: var(--kfm-tatami);
    border: 3px outset var(--kfm-tatami);
    cursor: pointer;
  }
  .act:hover { background: var(--kfm-belt-yellow); }
  .act:active { border-style: inset; }

  .act--respond { background: var(--kfm-belt-green); color: var(--kfm-parchment); border-color: var(--kfm-belt-green); }
  .act--respond:hover { filter: brightness(1.1); background: var(--kfm-belt-green); }

  .act--sent {
    background: transparent;
    border-style: inset;
    opacity: 0.55;
    cursor: default;
  }
</style>
