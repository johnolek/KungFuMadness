<script>
  // Renders a resolved fight as three scannable round panels — challenger column
  // on the left, defender on the right — with MoveIcon glyphs for each attack and
  // block and the fighter's HP after the round (before → after when they took a
  // hit). No damage prose, no animation. Panels sit side by side on desktop and
  // become a scroll-snap carousel on small screens.
  //
  // `reveal` is true only the first time a participant views their own fight:
  // rounds then step out one at a time. Spectators and repeat visits see it all.
  import MoveIcon from "./MoveIcon.svelte"
  import { beltChipStyle } from "./belt.js"

  let { fight, reveal = false } = $props()

  const HEIGHT = { 1: "low", 2: "mid", 3: "high" }
  const STYLE = { 0: "kick", 1: "punch" }

  let total = $derived(fight.rounds.length)
  // svelte-ignore state_referenced_locally -- islands remount per visit; props seed state once
  let revealed = $state(reveal ? 0 : fight.rounds.length)
  let done = $derived(revealed >= total)

  function beltColor(belt) {
    return `var(--belt-${Math.min(belt, 9)})`
  }

  // Damage this side TOOK in a round (the other side's dealt damage), which also
  // recovers their pre-round HP from the stored hp_after.
  function damageTaken(side, round) {
    return side === "challenger" ? round.opponent_damage : round.challenger_damage
  }

  function hpAfter(side, round) {
    return side === "challenger" ? round.challenger_hp_after : round.opponent_hp_after
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

  <div class="rounds">
    {#each fight.rounds as round, i}
      {#if i < revealed}
        {@const cMove = fight.challenger.moves[i]}
        {@const oMove = fight.opponent.moves[i]}
        {@const cTaken = damageTaken("challenger", round)}
        {@const oTaken = damageTaken("opponent", round)}
        {@const cAfter = hpAfter("challenger", round)}
        {@const oAfter = hpAfter("opponent", round)}
        {@const cAttackLanded = oTaken > 0}
        {@const oAttackLanded = cTaken > 0}
        {@const cBlockWorked = cTaken === 0}
        {@const oBlockWorked = oTaken === 0}
        <section class="rp">
          <header class="rp__head">
            Round {round.round}
            {#if fight.ko && i === total - 1}<span class="rp__ko">KO</span>{/if}
          </header>
          <!-- Grid rows pair the exchange: the challenger's attack sits beside the
               block the opponent answered it with, and vice versa below. -->
          <div class="rp__cols">
            <div class="rp__name" style={beltChipStyle(fight.challenger.belt)}>{fight.challenger.display_name}</div>
            <div class="rp__name" style={beltChipStyle(fight.opponent.belt)}>{fight.opponent.display_name}</div>

            <div class="rp__move" class:rp__move--good={cAttackLanded}>
              <MoveIcon kind="attack" height={cMove.attack_height} style={cMove.attack_style} size={26} />
              <span>{HEIGHT[cMove.attack_height]} {STYLE[cMove.attack_style]}</span>
            </div>
            <div class="rp__move" class:rp__move--good={oBlockWorked}>
              <MoveIcon kind="block" height={oMove.block_height} size={26} />
              <span>{HEIGHT[oMove.block_height]} block</span>
            </div>

            <div class="rp__move" class:rp__move--good={cBlockWorked}>
              <MoveIcon kind="block" height={cMove.block_height} size={26} />
              <span>{HEIGHT[cMove.block_height]} block</span>
            </div>
            <div class="rp__move" class:rp__move--good={oAttackLanded}>
              <MoveIcon kind="attack" height={oMove.attack_height} style={oMove.attack_style} size={26} />
              <span>{HEIGHT[oMove.attack_height]} {STYLE[oMove.attack_style]}</span>
            </div>

            <div class="rp__hp">
              {#if cTaken > 0}
                <span class="rp__hp-before">HP {cAfter + cTaken}</span>
                <span class="rp__hp-after" class:rp__hp-after--ko={cAfter < 1}>→ {cAfter}</span>
              {:else}
                <span class="rp__hp-steady">HP {cAfter}</span>
              {/if}
            </div>
            <div class="rp__hp">
              {#if oTaken > 0}
                <span class="rp__hp-before">HP {oAfter + oTaken}</span>
                <span class="rp__hp-after" class:rp__hp-after--ko={oAfter < 1}>→ {oAfter}</span>
              {:else}
                <span class="rp__hp-steady">HP {oAfter}</span>
              {/if}
            </div>
          </div>
        </section>
      {/if}
    {/each}
  </div>

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
      {#each [fight.challenger, fight.opponent] as fighter}
        {#if fighter.belt_change}
          <div class="banner__belt banner__belt--{fighter.belt_change.direction}">
            {#if fighter.belt_change.direction === "promotion"}
              {fighter.name} is promoted to {fighter.belt_change.to_belt_name} belt!
            {:else}
              {fighter.name} is demoted to {fighter.belt_change.to_belt_name} belt.
            {/if}
          </div>
        {/if}
      {/each}
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
    width: 72px;
    height: 96px;
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
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 0.6rem;
    align-items: start;
  }

  .rp {
    border: 3px solid var(--kfm-border, #1a1108);
    background: var(--kfm-panel, #fbf3dc);
  }

  .rp__head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.4rem;
    padding: 0.25rem 0.5rem;
    background: var(--kfm-ink, #1a1108);
    color: var(--kfm-parchment, #f4e4bc);
    font-weight: bold;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    font-size: 0.8rem;
  }

  .rp__ko {
    background: var(--kfm-belt-red, #b83d3d);
    padding: 0 0.35rem;
    font-size: 0.7rem;
  }

  .rp__cols {
    display: grid;
    grid-template-columns: 1fr 1fr;
    align-items: center;
    padding: 0.4rem 0;
  }

  .rp__cols > * {
    padding: 0.15rem 0.5rem;
    min-width: 0;
  }

  .rp__cols > :nth-child(even):not(.rp__name) {
    border-left: 1px dashed var(--kfm-ink-soft, #4a3a24);
  }

  .rp__name {
    margin: 0 0.5rem 0.25rem;
    padding: 0 0.25rem;
    border: 1px solid var(--kfm-border, #1a1108);
    font-size: 0.62rem;
    font-weight: bold;
    text-transform: uppercase;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .rp__move {
    display: flex;
    align-items: center;
    gap: 0.35rem;
    font-size: 0.72rem;
    text-transform: uppercase;
    letter-spacing: 0.02em;
    white-space: nowrap;
    color: var(--kfm-ink-soft, #4a3a24);
  }

  .rp__move--good {
    font-weight: bold;
    color: var(--kfm-ink, #1a1108);
  }

  .rp__hp {
    margin-top: 0.25rem;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.05rem;
    font-size: 0.8rem;
    font-variant-numeric: tabular-nums;
  }

  .rp__hp-before {
    color: var(--kfm-ink-soft, #4a3a24);
  }

  .rp__hp-steady {
    color: var(--kfm-ink, #1a1108);
    font-weight: bold;
  }

  .rp__hp-after {
    color: var(--kfm-belt-red, #b83d3d);
    font-weight: bold;
  }

  .rp__hp-after--ko {
    background: var(--kfm-ink, #1a1108);
    color: var(--kfm-parchment, #f4e4bc);
    padding: 0 0.35rem;
    border: 2px solid var(--kfm-belt-red, #b83d3d);
  }

  @media (max-width: 700px) {
    .rounds {
      display: flex;
      overflow-x: auto;
      scroll-snap-type: x mandatory;
      -webkit-overflow-scrolling: touch;
    }

    .rp {
      flex: 0 0 85%;
      scroll-snap-align: start;
    }
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

  .banner__belt {
    margin-top: 0.5rem;
    font-family: var(--kfm-font-display, "Courier New", monospace);
    font-weight: bold;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    font-size: 0.95rem;
  }
  .banner__belt--promotion { color: #7ed07e; }
  .banner__belt--demotion { color: #e88; }
</style>
