<script>
  // Renders a resolved fight clearly and plainly — NO animation. Two belt-colored
  // rectangles with names, a round-by-round results list revealed one at a time,
  // and an outcome banner with XP deltas once the fight has played out.
  let { fight } = $props()

  const HEIGHT = { 1: "low", 2: "mid", 3: "high" }
  const STYLE = { 0: "kicked", 1: "punched" }

  let revealed = $state(0)
  let total = $derived(fight.rounds.length)
  let done = $derived(revealed >= total)

  function beltColor(belt) {
    return `var(--belt-${Math.min(belt, 9)})`
  }

  function attackLine(name, move, damage) {
    const verb = STYLE[move.attack_style] ?? "struck"
    const height = HEIGHT[move.attack_height] ?? "?"
    const outcome = damage > 0 ? `landed for ${damage}` : "blocked"
    return `${name} ${verb} ${height} — ${outcome}`
  }

  let bannerText = $derived(
    fight.winner_side === null
      ? (fight.ko ? "Double knockout — DRAW" : "DRAW")
      : `${(fight.winner_side === "challenger" ? fight.challenger : fight.opponent).name} wins${fight.ko ? " by KNOCKOUT" : ""}`
  )

  function deltaClass(delta) {
    return delta >= 0 ? "xp-up" : "xp-down"
  }
</script>

<div class="playback">
  <div class="corners">
    {#each [fight.challenger, fight.opponent] as fighter}
      <div class="corner">
        <div class="corner__rect" style="background: {beltColor(fighter.belt)};"></div>
        <div class="corner__name">{fighter.display_name}</div>
        <div class="corner__belt">{fighter.belt_name} belt</div>
        <div class="corner__record">{fighter.record.wins}-{fighter.record.losses}-{fighter.record.draws}</div>
      </div>
    {/each}
  </div>

  <ol class="rounds">
    {#each fight.rounds as round, i}
      {#if i < revealed}
        <li class="round">
          <div class="round__head">Round {round.round}</div>
          <div>{attackLine(fight.challenger.name, fight.challenger.moves[i], round.challenger_damage)}</div>
          <div>{attackLine(fight.opponent.name, fight.opponent.moves[i], round.opponent_damage)}</div>
          <div class="round__hp">
            HP after — {fight.challenger.name}: {round.challenger_hp_after},
            {fight.opponent.name}: {round.opponent_hp_after}
          </div>
        </li>
      {/if}
    {/each}
  </ol>

  {#if !done}
    <div class="controls">
      <button type="button" class="pb-btn" onclick={() => (revealed = revealed + 1)}>Reveal next round</button>
      <button type="button" class="pb-btn" onclick={() => (revealed = total)}>Reveal all</button>
    </div>
  {/if}

  {#if done}
    <div class="banner">
      <div class="banner__result">{bannerText}</div>
      <div class="banner__xp">
        <span>{fight.challenger.name}:
          <strong class={deltaClass(fight.challenger.xp_delta)}>{fight.challenger.xp_delta} XP</strong>
        </span>
        <span>{fight.opponent.name}:
          <strong class={deltaClass(fight.opponent.xp_delta)}>{fight.opponent.xp_delta} XP</strong>
        </span>
      </div>
    </div>
  {/if}
</div>

<style>
  .playback {
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }

  .corners {
    display: flex;
    gap: 1.5rem;
    justify-content: center;
    flex-wrap: wrap;
  }

  .corner {
    text-align: center;
    min-width: 8rem;
  }

  .corner__rect {
    width: 96px;
    height: 128px;
    margin: 0 auto 0.4rem;
    border: 3px solid var(--kfm-border, #1a1108);
    box-shadow: 3px 3px 0 rgba(0, 0, 0, 0.4);
  }

  .corner__name {
    font-weight: bold;
    letter-spacing: 0.03em;
  }

  .corner__belt,
  .corner__record {
    font-size: 0.85rem;
    color: var(--kfm-ink-soft, #4a3a24);
  }

  .rounds {
    list-style: none;
    padding: 0;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .round {
    border: 3px solid var(--kfm-border, #1a1108);
    background: var(--kfm-panel, #fbf3dc);
    padding: 0.6rem 0.8rem;
  }

  .round__head {
    font-weight: bold;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    margin-bottom: 0.2rem;
  }

  .round__hp {
    margin-top: 0.3rem;
    font-size: 0.9rem;
    color: var(--kfm-ink-soft, #4a3a24);
  }

  .controls {
    display: flex;
    gap: 0.5rem;
  }

  .pb-btn {
    font-family: var(--kfm-font-display, "Courier New", monospace);
    font-weight: bold;
    text-transform: uppercase;
    padding: 0.4rem 0.9rem;
    color: var(--kfm-ink, #1a1108);
    background: var(--kfm-tatami, #e6d2a3);
    border: 4px outset var(--kfm-tatami, #e6d2a3);
    cursor: pointer;
  }

  .pb-btn:active {
    border-style: inset;
  }

  .banner {
    border: 4px solid var(--kfm-border, #1a1108);
    background: var(--kfm-ink, #1a1108);
    color: var(--kfm-parchment, #f4e4bc);
    padding: 0.8rem 1rem;
    text-align: center;
  }

  .banner__result {
    font-family: var(--kfm-font-display, "Courier New", monospace);
    font-size: 1.3rem;
    font-weight: bold;
    text-transform: uppercase;
    letter-spacing: 0.08em;
  }

  .banner__xp {
    display: flex;
    gap: 1.5rem;
    justify-content: center;
    margin-top: 0.5rem;
    flex-wrap: wrap;
  }

  .xp-up { color: #7ed07e; }
  .xp-down { color: #e88; }
</style>
