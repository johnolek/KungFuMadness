<script>
  // The dojo inbox: challenges to answer (incoming) and challenges you've sent
  // (outgoing). Rows are plain data-attribute buttons that open the shared modal.
  // Live via FighterChannel events (relayed as `kfm:fighter`) plus local echoes
  // from the modal when you send/answer.
  import { beltChipStyle } from "./belt.js"

  let { incoming: initialIncoming = [], outgoing: initialOutgoing = [] } = $props()

  // svelte-ignore state_referenced_locally -- islands remount per visit; props seed state once
  let incoming = $state(initialIncoming)
  // svelte-ignore state_referenced_locally
  let outgoing = $state(initialOutgoing)

  function prependUnique(list, card) {
    return list.some((c) => c.id === card.id) ? list : [card, ...list]
  }

  $effect(() => {
    const onFighter = (event) => {
      const message = event.detail
      const fight = message?.fight
      if (!fight) return
      if (message.event === "challenge_received") {
        incoming = prependUnique(incoming, fight)
      } else if (message.event === "challenge_resolved" || message.event === "challenge_declined") {
        outgoing = outgoing.filter((c) => c.id !== fight.id)
      }
    }
    // Local echoes from the modal so the inbox reacts without a round-trip.
    const onSent = (event) => {
      if (event.detail.card) outgoing = prependUnique(outgoing, event.detail.card)
    }
    const onRemove = (event) => {
      incoming = incoming.filter((c) => c.id !== event.detail.fightId)
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

<div class="dojo-grid">
  <section class="panel-kfm">
    <div class="panel-kfm-title">Challenges to answer</div>
    {#if incoming.length === 0}
      <p>No one dares challenge you right now.</p>
    {:else}
      {#each incoming as card (card.id)}
        <div class="challenge-row">
          <a class="chip" style={beltChipStyle(card.challenger.belt)} href={card.challenger_url}>{card.challenger.display_name}</a>
          <button type="button" class="btn-kfm btn-kfm--sm" data-respond-open={card.id}>Respond</button>
        </div>
      {/each}
    {/if}
  </section>

  <section class="panel-kfm">
    <div class="panel-kfm-title">Challenges you've sent</div>
    {#if outgoing.length === 0}
      <p>You have no challenges outstanding. <a href="/fighters">Find an opponent</a>.</p>
    {:else}
      {#each outgoing as card (card.id)}
        <div class="challenge-row">
          <a class="chip" style={beltChipStyle(card.opponent.belt)} href={card.opponent_url}>{card.opponent.display_name}</a>
          <span class="waiting">Awaiting reply…</span>
        </div>
      {/each}
    {/if}
  </section>
</div>

<style>
  .chip {
    display: inline-block;
    min-width: 0;
    padding: 0 0.35rem;
    border: 2px solid var(--kfm-border);
    font-size: 0.75rem;
    font-weight: bold;
    text-transform: uppercase;
    vertical-align: middle;
    text-decoration: none;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .waiting { color: var(--kfm-ink-soft); font-weight: bold; }
</style>
