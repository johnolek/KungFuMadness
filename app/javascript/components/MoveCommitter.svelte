<script>
  // Commit three rounds of moves. Renders its own <form> that POSTs to `action`
  // with a hidden `moves` field carrying the committed JSON, plus any extra
  // hidden fields (e.g. the opponent id, the Rails CSRF token). Shared by the
  // challenge-create and challenge-respond pages. No animation — chunky retro
  // controls only.
  let {
    action,
    method = "post",
    submitLabel = "Commit moves",
    csrfToken = "",
    hiddenFields = {}
  } = $props()

  const HEIGHTS = [
    { value: 1, label: "Low" },
    { value: 2, label: "Mid" },
    { value: 3, label: "High" }
  ]
  const STYLES = [
    { value: 0, label: "Kick" },
    { value: 1, label: "Punch" }
  ]

  let rounds = $state(
    [0, 1, 2].map(() => ({ attackHeight: null, attackStyle: 0, blockHeight: null }))
  )

  let complete = $derived(
    rounds.every((r) => r.attackHeight !== null && r.blockHeight !== null)
  )

  let movesJson = $derived(
    JSON.stringify(
      rounds.map((r, i) => ({
        round: i + 1,
        attack_height: r.attackHeight,
        attack_style: r.attackStyle,
        block_height: r.blockHeight
      }))
    )
  )

  let extraFields = $derived(Object.entries(hiddenFields))
</script>

<form {action} {method} class="committer">
  {#if csrfToken}
    <input type="hidden" name="authenticity_token" value={csrfToken} />
  {/if}
  {#each extraFields as [name, value]}
    <input type="hidden" {name} value={value} />
  {/each}
  <input type="hidden" name="moves" value={movesJson} />

  {#each rounds as round, i}
    <fieldset class="round">
      <legend>Round {i + 1}</legend>

      <div class="control">
        <span class="control__label">Attack</span>
        <div class="segmented">
          {#each HEIGHTS as h}
            <button
              type="button"
              class="seg"
              class:seg--on={round.attackHeight === h.value}
              onclick={() => (round.attackHeight = h.value)}
            >{h.label}</button>
          {/each}
        </div>
        <div class="segmented segmented--style">
          {#each STYLES as s}
            <button
              type="button"
              class="seg"
              class:seg--on={round.attackStyle === s.value}
              onclick={() => (round.attackStyle = s.value)}
            >{s.label}</button>
          {/each}
        </div>
      </div>

      <div class="control">
        <span class="control__label">Block</span>
        <div class="segmented">
          {#each HEIGHTS as h}
            <button
              type="button"
              class="seg"
              class:seg--on={round.blockHeight === h.value}
              onclick={() => (round.blockHeight = h.value)}
            >{h.label}</button>
          {/each}
        </div>
      </div>
    </fieldset>
  {/each}

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

  .round {
    border: 3px solid var(--kfm-border, #1a1108);
    background: var(--kfm-panel, #fbf3dc);
    padding: 0.75rem;
    margin: 0;
  }

  .round legend {
    font-weight: bold;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    padding: 0 0.4rem;
  }

  .control {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 0.5rem;
    margin: 0.4rem 0;
  }

  .control__label {
    min-width: 4rem;
    font-weight: bold;
    text-transform: uppercase;
    font-size: 0.85rem;
  }

  .segmented {
    display: inline-flex;
    gap: 2px;
  }

  .segmented--style {
    margin-left: 0.75rem;
  }

  .seg {
    font-family: var(--kfm-font-display, "Courier New", monospace);
    font-weight: bold;
    text-transform: uppercase;
    padding: 0.3rem 0.7rem;
    color: var(--kfm-ink, #1a1108);
    background: var(--kfm-tatami, #e6d2a3);
    border: 3px outset var(--kfm-tatami, #e6d2a3);
    cursor: pointer;
  }

  .seg:active {
    border-style: inset;
  }

  .seg--on {
    background: var(--kfm-belt-yellow, #e8c84a);
    border-style: inset;
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
