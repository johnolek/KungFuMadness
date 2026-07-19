// Inline style for a belt-colored name chip, matching the ERB `belt_chip` helper:
// light belts (index <= 3) take dark ink, darker belts take parchment text.
export function beltChipStyle(belt) {
  const dark = belt <= 3
  return `background: var(--belt-${Math.min(belt, 9)}); color: ${dark ? "var(--kfm-ink)" : "var(--kfm-parchment)"};`
}

// Coarse "N minutes ago" relative time from an ISO string, good enough for a
// living ticker (no library, no per-second churn).
export function relativeTime(iso) {
  if (!iso) return ""
  const seconds = Math.max(0, Math.floor((Date.now() - new Date(iso).getTime()) / 1000))
  if (seconds < 45) return "just now"
  const minutes = Math.floor(seconds / 60)
  if (minutes < 1) return "just now"
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h ago`
  const days = Math.floor(hours / 24)
  return `${days}d ago`
}
