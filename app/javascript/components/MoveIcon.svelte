<script>
  // Chunky placeholder glyph for a move, until real art lands: a stick fighter
  // with the relevant zone marked — high at the head, mid at the torso, low at
  // the legs. Attacks draw a foot (kick, wedge) or fist (punch, block) coming in
  // from the left in red; blocks draw a guard bar across the zone in blue.
  // Pure rects/polygons, no animation, inherits the button's text color for the
  // figure so it reads on any surface.
  let { kind = "attack", height = 2, style = 0, size = 30 } = $props()

  const ZONE_Y = { 3: 3, 2: 15, 1: 31 }
  let y = $derived(ZONE_Y[height] ?? 15)
</script>

<svg viewBox="0 0 36 44" width={size} height={Math.round((size * 44) / 36)} aria-hidden="true">
  <g fill="currentColor" opacity="0.8">
    <rect x="17" y="1" width="8" height="8" />
    <rect x="18" y="10" width="6" height="16" />
    <rect x="14" y="12" width="14" height="3" />
    <rect x="17" y="27" width="3" height="15" />
    <rect x="22" y="27" width="3" height="15" />
  </g>
  {#if kind === "attack"}
    <g fill="var(--kfm-belt-red, #b83d3d)">
      <rect x="0" y={y + 3} width="9" height="3" />
      {#if style === 0}
        <polygon points={`7,${y} 16,${y + 4} 7,${y + 9}`} />
      {:else}
        <rect x="8" y={y + 1} width="7" height="7" />
      {/if}
    </g>
  {:else}
    <rect x="11" y={y + 1} width="20" height="6" fill="var(--kfm-belt-blue, #3d6ab8)" />
  {/if}
</svg>
