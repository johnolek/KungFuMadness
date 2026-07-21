<script>
  // Right sidebar: fighters seen recently, one single-height row each — name as
  // a belt-colored chip — in a list that scrolls on its own, opening centered
  // on YOUR row (slotted in at rank) so the fighters near your level are the
  // first thing you see. Fighters who just went offline drop into their own
  // "Recently online" section below (dimmed, still challengeable — they may
  // have push notifications on) until their grace runs out, keeping the online
  // section pure. Other rows carry a challenge control shaped by your standing
  // toward them: Challenge (open the modal), a dimmed "Challenged" marker when
  // you already have one out, or Respond when they're waiting on you.
  //
  // Live: DojoChannel presence events (relayed as `kfm:dojo`) slide rows in and
  // between sections; your own actions and FighterChannel events flip a row's
  // challenge state.
  import { slide } from "svelte/transition"
  import { flip } from "svelte/animate"
  import { beltChipStyle } from "./belt.js"

  let { fighters: initial = [], youId } = $props()

  // Mirrors the server's Fighter::RECENT_OFFLINE_GRACE.
  const OFFLINE_GRACE_MS = 5 * 60 * 1000

  const reduceMotion =
    typeof matchMedia === "function" && matchMedia("(prefers-reduced-motion: reduce)").matches
  const slideIn = reduceMotion ? { duration: 0 } : { duration: 250 }
  const flipDuration = reduceMotion ? 0 : 200

  // svelte-ignore state_referenced_locally -- islands remount per visit; props seed state once
  let fighters = $state(initial)

  const online = $derived(fighters.filter((f) => f.online !== false))
  const offline = $derived(fighters.filter((f) => f.online === false))

  let listEl = $state(null)
  let centeredOnYou = false

  // Open the list scrolled so your row sits mid-view: the fighters around your
  // rank — the ones worth challenging — are what you land on. Once only; live
  // updates afterward must not yank the user's scroll position.
  $effect(() => {
    if (centeredOnYou || !listEl) return
    centeredOnYou = true
    if (listEl.scrollHeight <= listEl.clientHeight) return
    const youRow = listEl.querySelector(".online__row--you")
    if (!youRow) return
    const offset = youRow.getBoundingClientRect().top - listEl.getBoundingClientRect().top
    listEl.scrollTop = offset - (listEl.clientHeight - youRow.offsetHeight) / 2
  })

  const removalTimers = new Map()

  function clearRemoval(id) {
    const timer = removalTimers.get(id)
    if (timer) {
      clearTimeout(timer)
      removalTimers.delete(id)
    }
  }

  function scheduleRemoval(id, ms = OFFLINE_GRACE_MS) {
    clearRemoval(id)
    removalTimers.set(id, setTimeout(() => {
      removalTimers.delete(id)
      fighters = fighters.filter((f) => f.id !== id)
    }, Math.max(ms, 0)))
  }

  function upsertPresence(fighter) {
    if (fighter.id === youId) return
    clearRemoval(fighter.id)
    const existing = fighters.find((f) => f.id === fighter.id)
    if (existing) {
      Object.assign(existing, {
        name: fighter.name,
        display_name: fighter.display_name,
        belt: fighter.belt,
        belt_name: fighter.belt_name,
        url: fighter.url,
        online: true
      })
    } else {
      fighters = [...fighters, { ...fighter, challenge_state: "open", fight_id: null, online: true }]
    }
  }

  function markOffline(id) {
    if (id === youId) return
    const row = fighters.find((f) => f.id === id)
    if (!row) return
    row.online = false
    scheduleRemoval(id)
  }

  function setState(id, state, fightId = null) {
    if (id === youId) return
    const row = fighters.find((f) => f.id === id)
    if (row) {
      row.challenge_state = state
      row.fight_id = fightId
    }
  }

  // Server-seeded offline rows age out on the server's clock.
  $effect(() => {
    for (const row of initial) {
      if (row.online === false) {
        scheduleRemoval(row.id, (row.offline_expires_in ?? OFFLINE_GRACE_MS / 1000) * 1000)
      }
    }
    return () => {
      for (const timer of removalTimers.values()) clearTimeout(timer)
      removalTimers.clear()
    }
  })

  $effect(() => {
    const onDojo = (event) => {
      const message = event.detail
      if (message?.event !== "presence" || !message.fighter) return
      if (message.online) upsertPresence(message.fighter)
      else markOffline(message.fighter.id)
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

{#snippet actions(fighter)}
  {#if fighter.id === youId}
    <span class="act act--you">You</span>
  {:else if fighter.challenge_state === "respond"}
    <button type="button" class="act act--respond" data-respond-open={fighter.fight_id}>Respond</button>
  {:else if fighter.challenge_state === "challenged"}
    <span class="act act--sent" title="Waiting on their answer">Challenged</span>
  {:else}
    <button type="button" class="act" data-challenge-open={fighter.id}>Challenge</button>
  {/if}
{/snippet}

<section class="panel-kfm sidebar-panel">
  <div class="panel-kfm-title">Online now</div>
  {#if fighters.length === 0}
    <p class="empty">The dojo is quiet. No one else is on the mat.</p>
  {:else}
    <div class="scroller" bind:this={listEl}>
      {#if online.length === 0}
        <p class="empty">No one is on the mat right now.</p>
      {:else}
        <ul class="online">
          {#each online as fighter (fighter.id)}
            <li
              class="online__row"
              class:online__row--you={fighter.id === youId}
              transition:slide={slideIn}
              animate:flip={{ duration: flipDuration }}
            >
              <a class="online__name" href={fighter.url}>
                <span class="chip" style={beltChipStyle(fighter.belt)}>{fighter.display_name}</span>
              </a>
              {@render actions(fighter)}
            </li>
          {/each}
        </ul>
      {/if}

      {#if offline.length > 0}
        <div class="subhead" transition:slide={slideIn}>Recently online</div>
        <ul class="online">
          {#each offline as fighter (fighter.id)}
            <li
              class="online__row online__row--offline"
              transition:slide={slideIn}
              animate:flip={{ duration: flipDuration }}
            >
              <a class="online__name" href={fighter.url}>
                <span class="chip" style={beltChipStyle(fighter.belt)}>{fighter.display_name}</span>
              </a>
              {@render actions(fighter)}
            </li>
          {/each}
        </ul>
      {/if}
    </div>
  {/if}
</section>

<style>
  .sidebar-panel { margin-bottom: 0; }

  .empty { color: var(--kfm-ink-soft); font-size: 0.85rem; }

  /* No overscroll-behavior: contain here — when the list hits its top or
     bottom the scroll must chain to the page, or mobile users get stuck. */
  .scroller {
    max-height: min(60vh, 28rem);
    overflow-y: auto;
  }

  .online {
    list-style: none;
    margin: 0;
    padding: 0;
  }

  .subhead {
    margin: 0.6rem 0 0.15rem;
    font-size: 0.62rem;
    font-weight: bold;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--kfm-ink-soft);
    border-bottom: 1px solid var(--kfm-ink-soft);
  }

  .online__row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.4rem;
    padding: 0.25rem 0.15rem;
    border-bottom: 1px dashed var(--kfm-ink-soft);
    white-space: nowrap;
  }
  .online__row:last-child { border-bottom: none; }

  .online__row--you {
    background: rgba(0, 0, 0, 0.06);
    outline: 2px solid var(--kfm-ink-soft);
  }

  .online__row--offline {
    opacity: 0.45;
  }

  .online__row--offline:hover {
    opacity: 0.8;
  }

  .online__name {
    text-decoration: none;
    min-width: 0;
    flex: 1 1 auto;
    overflow: hidden;
  }

  .chip {
    display: block;
    max-width: 100%;
    width: fit-content;
    padding: 0 0.3rem;
    border: 1px solid var(--kfm-border);
    font-size: 0.68rem;
    font-weight: bold;
    text-transform: uppercase;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .online__name:hover .chip { filter: brightness(1.1); }

  .act {
    flex: none;
    font-family: var(--kfm-font-display, "Courier New", monospace);
    font-weight: bold;
    text-transform: uppercase;
    font-size: 0.6rem;
    letter-spacing: 0.04em;
    padding: 0.15rem 0.4rem;
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

  .act--you {
    background: var(--kfm-ink);
    color: var(--kfm-parchment);
    border-color: var(--kfm-ink);
    cursor: default;
  }
</style>
