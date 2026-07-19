<script>
  // One modal instance mounted in the layout. It opens on custom DOM events
  // dispatched by plain data-attribute buttons anywhere on the page:
  //   kfm:challenge-open { opponentId }  → challenge mode (pick moves, send)
  //   kfm:respond-open   { fightId }     → respond mode (accept-with-moves / decline)
  // Data comes from JSON endpoints (sealed-move discipline preserved); submission
  // is fetch + CSRF; success closes the modal, toasts, and echoes sidebar/inbox
  // state via more custom events.
  import MoveGrid from "./MoveGrid.svelte"
  import { beltChipStyle } from "./belt.js"

  let { csrfToken = "" } = $props()

  let open = $state(false)
  let loading = $state(false)
  let submitting = $state(false)
  let error = $state("")
  let mode = $state("challenge")
  let data = $state(null)
  let opponentId = $state(null)
  let fightId = $state(null)
  let moves = $state([])
  let complete = $state(false)

  const RESULT_LABEL = { win: "Won", loss: "Lost", draw: "Draw" }

  function toast(type, message) {
    document.dispatchEvent(new CustomEvent("toast", { detail: { type, message } }))
  }

  function reset() {
    data = null
    error = ""
    moves = []
    complete = false
    submitting = false
  }

  function close() {
    open = false
    reset()
  }

  async function loadJson(url) {
    const response = await fetch(url, { headers: { Accept: "application/json" } })
    const payload = await response.json().catch(() => ({}))
    if (!response.ok) throw new Error(payload.error || "Something went wrong.")
    return payload
  }

  async function openChallenge(id) {
    open = true
    loading = true
    reset()
    opponentId = id
    fightId = null
    mode = "challenge"
    try {
      data = await loadJson(`/challenges/new.json?opponent=${id}`)
    } catch (e) {
      error = e.message
    } finally {
      loading = false
    }
  }

  async function openRespond(id) {
    open = true
    loading = true
    reset()
    fightId = id
    opponentId = null
    mode = "respond"
    try {
      data = await loadJson(`/challenges/${id}.json`)
    } catch (e) {
      error = e.message
    } finally {
      loading = false
    }
  }

  async function post(url, body) {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": csrfToken
      },
      body: JSON.stringify(body)
    })
    const payload = await response.json().catch(() => ({}))
    return { ok: response.ok, payload }
  }

  async function send() {
    if (!complete || submitting) return
    submitting = true
    error = ""
    const { ok, payload } = await post(data.action, { opponent: opponentId, moves })
    if (ok) {
      toast("notice", payload.message || "Challenge sent")
      document.dispatchEvent(new CustomEvent("kfm:challenge-sent", {
        detail: { opponentId, card: payload.card }
      }))
      close()
    } else {
      error = payload.error || "That challenge couldn't be sent."
      submitting = false
    }
  }

  async function accept() {
    if (!complete || submitting) return
    submitting = true
    error = ""
    const { ok, payload } = await post(data.accept_url, { moves })
    if (ok) {
      document.dispatchEvent(new CustomEvent("kfm:inbox-remove", { detail: { fightId } }))
      close()
      window.Turbo ? window.Turbo.visit(payload.redirect_url) : (window.location = payload.redirect_url)
    } else {
      error = payload.error || "That challenge couldn't be answered."
      submitting = false
    }
  }

  async function decline() {
    if (submitting) return
    submitting = true
    error = ""
    const { ok, payload } = await post(data.decline_url, {})
    if (ok) {
      toast("info", payload.message || "Challenge declined")
      document.dispatchEvent(new CustomEvent("kfm:inbox-remove", { detail: { fightId } }))
      close()
    } else {
      error = payload.error || "That challenge couldn't be declined."
      submitting = false
    }
  }

  function onGrid(state) {
    moves = state.moves
    complete = state.complete
  }

  function onKeydown(event) {
    if (event.key === "Escape" && open) close()
  }

  $effect(() => {
    const onChallenge = (event) => openChallenge(event.detail.opponentId)
    const onRespond = (event) => openRespond(event.detail.fightId)
    document.addEventListener("kfm:challenge-open", onChallenge)
    document.addEventListener("kfm:respond-open", onRespond)
    document.addEventListener("keydown", onKeydown)
    return () => {
      document.removeEventListener("kfm:challenge-open", onChallenge)
      document.removeEventListener("kfm:respond-open", onRespond)
      document.removeEventListener("keydown", onKeydown)
    }
  })
</script>

{#if open}
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div class="backdrop" onclick={close} role="presentation">
    <!-- svelte-ignore a11y_click_events_have_key_events -->
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div class="modal panel-kfm" role="dialog" aria-modal="true" aria-label="Challenge" tabindex="-1"
         onclick={(e) => e.stopPropagation()}>
      <div class="panel-kfm-title modal__title">
        {mode === "challenge" ? "Send a challenge" : "Answer the challenge"}
        <button type="button" class="modal__x" aria-label="Close" onclick={close}>×</button>
      </div>

      {#if loading}
        <p>Loading…</p>
      {:else if error && !data}
        <p class="modal__error">{error}</p>
        <button type="button" class="btn-kfm" onclick={close}>Close</button>
      {:else if data}
        <div class="opp">
          <span class="chip" style={beltChipStyle(data.opponent.belt)}>{data.opponent.belt_name}</span>
          <a class="opp__name" href={data.opponent.url}>{data.opponent.display_name}</a>
          <span class="opp__record">Record {data.opponent.record}</span>
        </div>

        <details class="scout">
          <summary>Scouting — last {data.scouting.length} fights</summary>
          {#if data.scouting.length === 0}
            <p class="scout__empty">No resolved fights on record. You're stepping into the unknown.</p>
          {:else}
            <table class="stat-table scout__table">
              <thead><tr><th>Date</th><th>Vs</th><th>Belt</th><th>Result</th><th></th></tr></thead>
              <tbody>
                {#each data.scouting as row (row.id)}
                  <tr>
                    <td>{row.date}</td>
                    <td>{row.opponent_name}</td>
                    <td><span class="chip" style={beltChipStyle(row.opponent_belt)}>{row.opponent_belt}</span></td>
                    <td class="res res--{row.result}">{RESULT_LABEL[row.result]}{row.ko ? " (KO)" : ""}</td>
                    <td><a href={row.url}>Watch</a></td>
                  </tr>
                {/each}
              </tbody>
            </table>
          {/if}
        </details>

        <p class="modal__hint">Commit all three rounds — your opponent answers blind.</p>
        <MoveGrid onchange={onGrid} />

        {#if error}<p class="modal__error">{error}</p>{/if}

        <div class="modal__actions">
          {#if mode === "challenge"}
            <button type="button" class="btn-kfm btn-kfm--go" disabled={!complete || submitting} onclick={send}>
              {submitting ? "Sending…" : complete ? "Send challenge" : "Choose every round"}
            </button>
          {:else}
            <button type="button" class="btn-kfm btn-kfm--go" disabled={!complete || submitting} onclick={accept}>
              {submitting ? "Working…" : complete ? "Accept & fight" : "Choose every round"}
            </button>
            <button type="button" class="btn-kfm btn-kfm--decline" disabled={submitting} onclick={decline}>Decline</button>
          {/if}
          <button type="button" class="btn-kfm" disabled={submitting} onclick={close}>Cancel</button>
        </div>
      {/if}
    </div>
  </div>
{/if}

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    z-index: 900;
    background: rgba(0, 0, 0, 0.6);
    display: flex;
    align-items: flex-start;
    justify-content: center;
    padding: 2rem 1rem;
    overflow-y: auto;
  }

  .modal {
    width: min(560px, 100%);
    margin: 0;
    max-height: calc(100vh - 4rem);
    overflow-y: auto;
  }

  .modal__title {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .modal__x {
    border: none;
    background: transparent;
    color: inherit;
    font-size: 1.3rem;
    line-height: 1;
    cursor: pointer;
    padding: 0;
  }

  .opp {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    flex-wrap: wrap;
    margin-bottom: 0.5rem;
  }
  .opp__name { font-weight: bold; }
  .opp__record { color: var(--kfm-ink-soft); font-size: 0.85rem; }

  .chip {
    display: inline-block;
    padding: 0 0.35rem;
    border: 2px solid var(--kfm-border);
    font-size: 0.72rem;
    font-weight: bold;
    text-transform: uppercase;
    vertical-align: middle;
  }

  .scout { margin: 0.5rem 0 0.75rem; }
  .scout summary { cursor: pointer; font-weight: bold; text-transform: uppercase; font-size: 0.8rem; }
  .scout__empty { font-size: 0.85rem; color: var(--kfm-ink-soft); }
  .scout__table { margin-top: 0.5rem; font-size: 0.8rem; }

  .res--win { color: var(--kfm-belt-green); font-weight: bold; }
  .res--loss { color: var(--kfm-belt-red); font-weight: bold; }
  .res--draw { color: var(--kfm-ink-soft); font-weight: bold; }

  .modal__hint { font-size: 0.85rem; margin: 0.5rem 0; }
  .modal__error { color: var(--kfm-belt-red); font-weight: bold; }

  .modal__actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    margin-top: 1rem;
  }

  .btn-kfm--go { background: var(--kfm-belt-green); border-color: var(--kfm-belt-green); color: var(--kfm-parchment); }
  .btn-kfm--go:hover { background: var(--kfm-belt-green); filter: brightness(1.1); }
  .btn-kfm--decline { background: var(--kfm-belt-red); border-color: var(--kfm-belt-red); color: var(--kfm-parchment); }
  .btn-kfm--go:disabled { opacity: 0.5; }
</style>
