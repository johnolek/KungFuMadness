<script>
  // THE match-history table — dojo homepage, profiles, and challenge scouting
  // panels all mount this island, so every history surface is live: rows are
  // seeded from Fight#history_row_payload and new ones prepend when a DojoChannel
  // fight_resolved broadcast (relayed as `kfm:dojo`) involves `fighterId`, read
  // from that fighter's perspective. Global stat-table/move-set styling keeps it
  // identical everywhere.
  import MoveIcon from "./MoveIcon.svelte"
  import { beltChipStyle } from "./belt.js"

  let {
    fights: initial = [], fighterId, showXp = true, emptyMessage = null,
    viewerId = null, hideSpoilers = false
  } = $props()

  const RESULT_LABEL = { win: "Won", loss: "Lost", draw: "Draw" }

  // svelte-ignore state_referenced_locally -- islands remount per visit; props seed state once
  let fights = $state(initial)

  function rowFromTicker(fight) {
    const mineSide =
      fight.challenger?.id === fighterId ? "challenger"
      : fight.opponent?.id === fighterId ? "opponent"
      : null
    if (!mineSide) return null
    const mine = fight[mineSide]
    const other = mineSide === "challenger" ? fight.opponent : fight.challenger
    const base = {
      id: fight.id,
      url: fight.url,
      opponent_name: other.display_name,
      opponent_belt: other.belt,
      opponent_url: other.url
    }
    // The public broadcast is unmasked; a fresh fight of the VIEWER's is by
    // definition unwatched, so mask it here when they keep spoilers hidden.
    const viewerInvolved = fight.challenger?.id === viewerId || fight.opponent?.id === viewerId
    if (hideSpoilers && viewerInvolved) {
      return { ...base, moves: [], result: null, ko: null, xp_delta: null, masked: true }
    }
    const result =
      fight.winner_side === null ? "draw" : fight.winner_side === mineSide ? "win" : "loss"
    return { ...base, moves: mine.moves ?? [], result, ko: fight.ko, xp_delta: mine.xp_delta }
  }

  $effect(() => {
    const handler = (event) => {
      const message = event.detail
      if (message?.event !== "fight_resolved" || !message.fight) return
      const row = rowFromTicker(message.fight)
      if (!row || fights.some((f) => f.id === row.id)) return
      fights = [row, ...fights]
    }
    document.addEventListener("kfm:dojo", handler)
    return () => document.removeEventListener("kfm:dojo", handler)
  })
</script>

{#if fights.length === 0}
  {#if emptyMessage}
    <p>{emptyMessage}</p>
  {:else}
    <p>No fights on record yet. <a href="/fighters">Find an opponent</a>.</p>
  {/if}
{:else}
  <div class="table-scroll">
    <table class="stat-table">
      <thead>
        <tr>
          <th>Opponent</th>
          <th>Moves</th>
          <th>Result</th>
          {#if showXp}<th>XP</th>{/if}
          <th></th>
        </tr>
      </thead>
      <tbody>
        {#each fights as row (row.id)}
          <tr>
            <td>
              <a class="belt-link" href={row.opponent_url}>
                <span class="belt-chip" style={beltChipStyle(row.opponent_belt)}>{row.opponent_name}</span>
              </a>
            </td>
            <td class="moves-cell">
              <span class="move-set">
                <span class="move-set__row">
                  {#each row.moves as move, i (i)}
                    <MoveIcon kind="attack" height={move[0]} style={move[1]} size={15} />
                  {/each}
                </span>
                <span class="move-set__row">
                  {#each row.moves as move, i (i)}
                    <MoveIcon kind="block" height={move[2]} size={15} />
                  {/each}
                </span>
              </span>
            </td>
            <td>
              {#if row.masked}
                <span class="result-masked" title="You haven't watched this fight yet">???</span>
              {:else}
                <span class="result-{row.result}">{RESULT_LABEL[row.result]}{row.ko ? " (KO)" : ""}</span>
              {/if}
            </td>
            {#if showXp}
              <td>
                {#if row.xp_delta !== null && row.xp_delta !== undefined}
                  <span class={row.xp_delta >= 0 ? "xp-up" : "xp-down"}>{row.xp_delta}</span>
                {/if}
              </td>
            {/if}
            <td><a href={row.url}>{row.masked ? "Watch to reveal" : "Watch"}</a></td>
          </tr>
        {/each}
      </tbody>
    </table>
  </div>
{/if}
