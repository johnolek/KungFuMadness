<script>
  let { greeting = "Welcome to the dojo." } = $props()

  let bows = $state(0)
</script>

<div class="dojo-placeholder">
  <p class="greeting">{greeting}</p>
  <button class="bow-button" onclick={() => bows++}>
    Bow ({bows})
  </button>
  {#if bows > 0}
    <p class="bow-count">You have bowed {bows} {bows === 1 ? "time" : "times"}. Respect.</p>
  {/if}
</div>

<style>
  .dojo-placeholder {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 0.5rem;
  }

  .greeting {
    margin: 0;
    font-weight: bold;
    letter-spacing: 0.03em;
  }

  .bow-button {
    font-family: "Courier New", monospace;
    font-weight: bold;
    padding: 0.35rem 0.9rem;
    background: #d9b779;
    color: #1a1108;
    border: 3px outset #b8935a;
    cursor: pointer;
  }

  .bow-button:active {
    border-style: inset;
  }

  .bow-count {
    margin: 0;
    font-style: italic;
  }
</style>
