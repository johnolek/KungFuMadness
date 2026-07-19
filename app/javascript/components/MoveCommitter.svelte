<script>
  // Non-modal fallback committer: renders a <form> that POSTs to `action` with a
  // hidden `moves` field carrying the committed JSON, plus any extra hidden fields
  // (opponent id, CSRF token). The move-picking UI is the shared MoveGrid; this
  // wrapper only handles form submission for the /challenges/new and respond pages.
  import MoveGrid from "./MoveGrid.svelte"

  let {
    action,
    method = "post",
    submitLabel = "Commit moves",
    csrfToken = "",
    hiddenFields = {}
  } = $props()

  let moves = $state([])
  let complete = $state(false)

  let movesJson = $derived(JSON.stringify(moves))
  let extraFields = $derived(Object.entries(hiddenFields))

  function onchange(state) {
    moves = state.moves
    complete = state.complete
  }
</script>

<form {action} {method} class="committer">
  {#if csrfToken}
    <input type="hidden" name="authenticity_token" value={csrfToken} />
  {/if}
  {#each extraFields as [name, value]}
    <input type="hidden" {name} value={value} />
  {/each}
  <input type="hidden" name="moves" value={movesJson} />

  <MoveGrid {onchange} />

  <button type="submit" class="commit-btn" disabled={!complete}>
    {complete ? submitLabel : "Choose every round first"}
  </button>
</form>

<style>
  .committer {
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }

  .commit-btn {
    font-family: var(--kfm-font-display, "Courier New", monospace);
    font-weight: bold;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    padding: 0.5rem 1rem;
    color: var(--kfm-ink, #1a1108);
    background: var(--kfm-belt-green, #4a8a4a);
    border: 4px outset var(--kfm-belt-green, #4a8a4a);
    cursor: pointer;
    align-self: flex-start;
  }

  .commit-btn:active {
    border-style: inset;
  }

  .commit-btn:disabled {
    background: var(--kfm-tatami, #e6d2a3);
    border-color: var(--kfm-tatami, #e6d2a3);
    color: var(--kfm-ink-soft, #4a3a24);
    cursor: not-allowed;
  }
</style>
