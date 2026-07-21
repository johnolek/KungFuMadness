<script>
  // Little nav counters for your pending challenges: IN (waiting on your answer)
  // and OUT (awaiting the opponent's reply). Seeded with the fight ids the server
  // counted, then kept live off the same events that drive the inbox — id sets,
  // not raw counts, so a repeated broadcast can't double-count. Both link to the
  // dojo, where the inbox lives. Incoming expiry has no personal broadcast, so
  // that count self-corrects on the next page load, same as the inbox.
  let { incomingIds = [], outgoingIds = [] } = $props()

  // svelte-ignore state_referenced_locally -- islands remount per visit; props seed state once
  let incoming = $state([...new Set(incomingIds)])
  // svelte-ignore state_referenced_locally
  let outgoing = $state([...new Set(outgoingIds)])

  const add = (list, id) => (id == null || list.includes(id) ? list : [...list, id])
  const drop = (list, id) => list.filter((x) => x !== id)

  $effect(() => {
    const onFighter = (event) => {
      const message = event.detail
      const fight = message?.fight
      if (!fight) return
      if (message.event === "challenge_received") {
        incoming = add(incoming, fight.id)
      } else if (["challenge_resolved", "challenge_declined", "challenge_expired"].includes(message.event)) {
        outgoing = drop(outgoing, fight.id)
        incoming = drop(incoming, fight.id)
      }
    }
    const onSent = (event) => {
      outgoing = add(outgoing, event.detail.card?.id)
    }
    const onRemove = (event) => {
      incoming = drop(incoming, event.detail.fightId)
    }
    document.addEventListener("kfm:fighter", onFighter)
    document.addEventListener("kfm:challenge-sent", onSent)
    document.addEventListener("kfm:inbox-remove", onRemove)
    return () => {
      document.removeEventListener("kfm:fighter", onFighter)
      document.removeEventListener("kfm:challenge-sent", onSent)
      document.removeEventListener("kfm:inbox-remove", onRemove)
    }
  })
</script>

{#if incoming.length > 0 || outgoing.length > 0}
  <span class="badges">
    {#if incoming.length > 0}
      <a class="badge badge--in" href="/" title="Challenges waiting on your answer">{incoming.length} in</a>
    {/if}
    {#if outgoing.length > 0}
      <a class="badge badge--out" href="/" title="Your challenges awaiting a reply">{outgoing.length} out</a>
    {/if}
  </span>
{/if}

<style>
  .badges {
    display: inline-flex;
    align-items: center;
    gap: 0.3rem;
  }

  .badge {
    display: inline-block;
    padding: 0.05rem 0.4rem;
    border: 1px solid var(--kfm-border);
    font-size: 0.68rem;
    font-weight: bold;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    text-decoration: none;
    white-space: nowrap;
  }

  .badge--in {
    background: var(--kfm-belt-green);
    color: var(--kfm-parchment);
  }

  .badge--out {
    background: var(--kfm-tatami);
    color: var(--kfm-ink);
  }

  .badge:hover { filter: brightness(1.1); }
</style>
