<script>
  // The bare 3-round attack/block picker, no <form> and no submit — reused by the
  // MoveCommitter (which wraps it in a POSTing form) and the ChallengeModal (which
  // submits the moves over fetch). Rounds run HORIZONTALLY — three columns side by
  // side — with MoveIcon glyphs showing where each height strikes or guards.
  // Reports its state up via onchange so the parent owns submission.
  import MoveIcon from "./MoveIcon.svelte"

  let { onchange } = $props()

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

  let moves = $derived(
    rounds.map((r, i) => ({
      round: i + 1,
      attack_height: r.attackHeight,
      attack_style: r.attackStyle,
      block_height: r.blockHeight
    }))
  )

  $effect(() => {
    onchange?.({ moves, complete })
  })
</script>

<div class="grid-scroll">
  <div class="grid">
    {#each rounds as round, i}
      <fieldset class="round">
        <legend>Round {i + 1}</legend>

        <span class="control__label">Attack</span>
        <div class="options">
          {#each HEIGHTS as h}
            <button
              type="button"
              class="seg seg--icon"
              class:seg--on={round.attackHeight === h.value}
              onclick={() => (round.attackHeight = h.value)}
            >
              <MoveIcon kind="attack" height={h.value} style={round.attackStyle} />
              <span class="seg__txt">{h.label}</span>
            </button>
          {/each}
        </div>
        <div class="styles">
          {#each STYLES as s}
            <button
              type="button"
              class="seg seg--sm"
              class:seg--on={round.attackStyle === s.value}
              onclick={() => (round.attackStyle = s.value)}
            >{s.label}</button>
          {/each}
        </div>

        <span class="control__label">Block</span>
        <div class="options">
          {#each HEIGHTS as h}
            <button
              type="button"
              class="seg seg--icon"
              class:seg--on={round.blockHeight === h.value}
              onclick={() => (round.blockHeight = h.value)}
            >
              <MoveIcon kind="block" height={h.value} />
              <span class="seg__txt">{h.label}</span>
            </button>
          {/each}
        </div>
      </fieldset>
    {/each}
  </div>
</div>

<style>
  .grid-scroll {
    overflow-x: auto;
    -webkit-overflow-scrolling: touch;
  }

  .grid {
    display: grid;
    grid-template-columns: repeat(3, minmax(9.5rem, 1fr));
    gap: 0.6rem;
  }

  .round {
    border: 3px solid var(--kfm-border, #1a1108);
    background: var(--kfm-panel, #fbf3dc);
    padding: 0.5rem;
    margin: 0;
    min-width: 0;
  }

  .round legend {
    font-weight: bold;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    padding: 0 0.4rem;
  }

  .control__label {
    display: block;
    font-weight: bold;
    text-transform: uppercase;
    font-size: 0.72rem;
    letter-spacing: 0.04em;
    margin: 0.4rem 0 0.2rem;
    color: var(--kfm-ink-soft, #4a3a24);
  }

  .options {
    display: flex;
    gap: 2px;
  }

  .styles {
    display: flex;
    gap: 2px;
    margin-top: 0.25rem;
  }

  .seg {
    font-family: var(--kfm-font-display, "Courier New", monospace);
    font-weight: bold;
    text-transform: uppercase;
    color: var(--kfm-ink, #1a1108);
    background: var(--kfm-tatami, #e6d2a3);
    border: 3px outset var(--kfm-tatami, #e6d2a3);
    cursor: pointer;
  }

  .seg--icon {
    flex: 1 1 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 1px;
    padding: 0.25rem 0.1rem 0.15rem;
    min-width: 0;
  }

  .seg__txt {
    font-size: 0.6rem;
    letter-spacing: 0.03em;
  }

  .seg--sm {
    flex: 1 1 0;
    padding: 0.2rem 0.4rem;
    font-size: 0.7rem;
  }

  .seg:active {
    border-style: inset;
  }

  .seg--on {
    background: var(--kfm-belt-yellow, #e8c84a);
    border-style: inset;
  }
</style>
