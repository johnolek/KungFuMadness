// The living-world wiring that lives outside the Svelte islands: a modal-open
// event bus driven by plain data attributes, and the ActionCable subscriptions
// that feed every island. Kept in one place so buttons rendered from ERB work
// without a per-button island, and so there is exactly one dojo/fighter
// subscription and one presence ping loop per browser.
import consumer from "./cable"

const PING_INTERVAL = 45000

function dispatch(name, detail) {
  document.dispatchEvent(new CustomEvent(name, { detail }))
}

function toast(type, message) {
  dispatch("toast", { type, message })
}

// --- modal-open bus ---------------------------------------------------------
// Any [data-challenge-open="<fighterId>"] or [data-respond-open="<fightId>"]
// element opens the shared modal. Anchors keep their href as a no-JS fallback.
document.addEventListener("click", (event) => {
  const challenge = event.target.closest("[data-challenge-open]")
  if (challenge) {
    event.preventDefault()
    dispatch("kfm:challenge-open", { opponentId: Number(challenge.dataset.challengeOpen) })
    return
  }
  const respond = event.target.closest("[data-respond-open]")
  if (respond) {
    event.preventDefault()
    dispatch("kfm:respond-open", { fightId: Number(respond.dataset.respondOpen) })
  }
})

// --- cable subscriptions ----------------------------------------------------
// Established once for a verified fighter and kept alive across Turbo visits
// (the DojoChannel subscribe is the "log on" that stamps presence).
let started = false
let dojoSubscription = null

function relayFighterToast(message) {
  const fight = message.fight
  if (message.event === "challenge_received") {
    const name = fight?.challenger?.display_name ?? "Someone"
    toast("notice", `${name} challenges you!`)
  } else if (message.event === "challenge_resolved") {
    const opponent = fight?.opponent?.display_name ?? "your opponent"
    const outcome =
      fight?.winner_side === "challenger" ? "you won!"
      : fight?.winner_side === "opponent" ? "you lost."
      : "it was a draw."
    toast(fight?.winner_side === "challenger" ? "notice" : "info", `Your fight with ${opponent} — ${outcome}`)
  } else if (message.event === "challenge_declined") {
    const name = fight?.opponent?.display_name ?? "Your opponent"
    toast("info", `${name} declined your challenge.`)
  }
}

function startLivingWorld() {
  if (started) return
  if (document.body?.dataset.kfmLive !== "true") return
  started = true

  dojoSubscription = consumer.subscriptions.create({ channel: "DojoChannel" }, {
    received: (message) => dispatch("kfm:dojo", message),
  })

  consumer.subscriptions.create({ channel: "FighterChannel" }, {
    received: (message) => {
      dispatch("kfm:fighter", message)
      relayFighterToast(message)
    },
  })

  setInterval(() => dojoSubscription?.perform("ping"), PING_INTERVAL)
}

document.addEventListener("turbo:load", startLivingWorld)
if (document.readyState !== "loading") startLivingWorld()
else document.addEventListener("DOMContentLoaded", startLivingWorld)
