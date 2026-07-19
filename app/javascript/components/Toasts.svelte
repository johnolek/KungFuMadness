<script>
  import { fly, fade } from "svelte/transition"
  import { flip } from "svelte/animate"

  let { toasts: initial = [] } = $props()

  const DURATION = 5000
  const reduceMotion =
    typeof matchMedia === "function" && matchMedia("(prefers-reduced-motion: reduce)").matches

  let nextId = 0
  // svelte-ignore state_referenced_locally -- islands remount per visit; props seed state once
  let toasts = $state(initial.map((toast) => ({ ...toast, id: nextId++ })))

  function add(toast) {
    toasts.push({ ...toast, id: nextId++ })
  }

  function dismiss(id) {
    const index = toasts.findIndex((toast) => toast.id === id)
    if (index !== -1) toasts.splice(index, 1)
  }

  function kindClass(type) {
    if (type === "notice") return "is-notice"
    if (type === "alert") return "is-alert"
    return "is-info"
  }

  // Each toast auto-dismisses after DURATION; the timer pauses while the toast
  // is hovered or focused so it can be read (and its close button reached).
  function autodismiss(node, id) {
    let remaining = DURATION
    let startedAt
    let timer

    function start() {
      startedAt = Date.now()
      timer = setTimeout(() => dismiss(id), remaining)
    }

    function pause() {
      clearTimeout(timer)
      remaining -= Date.now() - startedAt
    }

    node.addEventListener("mouseenter", pause)
    node.addEventListener("mouseleave", start)
    node.addEventListener("focusin", pause)
    node.addEventListener("focusout", start)
    start()

    return {
      destroy() {
        clearTimeout(timer)
        node.removeEventListener("mouseenter", pause)
        node.removeEventListener("mouseleave", start)
        node.removeEventListener("focusin", pause)
        node.removeEventListener("focusout", start)
      },
    }
  }

  // Other islands can raise a toast client-side by dispatching on document:
  // document.dispatchEvent(new CustomEvent("toast", { detail: { type, message } }))
  $effect(() => {
    const handler = (event) => add(event.detail)
    document.addEventListener("toast", handler)
    return () => document.removeEventListener("toast", handler)
  })

  // Reduced motion keeps the opacity fade but drops the vertical slide (y: 0).
  const flyIn = reduceMotion ? { y: 0, duration: 200 } : { y: -16, duration: 250 }
  const flipDuration = reduceMotion ? 0 : 200
</script>

<div class="toast-stack">
  {#each toasts as toast (toast.id)}
    <div
      class="toast {kindClass(toast.type)}"
      role="status"
      aria-live="polite"
      in:fly={flyIn}
      out:fade={{ duration: 200 }}
      animate:flip={{ duration: flipDuration }}
      use:autodismiss={toast.id}
    >
      <button class="toast-close" aria-label="Dismiss notification" onclick={() => dismiss(toast.id)}>×</button>
      <span class="toast-message">{toast.message}</span>
    </div>
  {/each}
</div>

<style>
  .toast-stack {
    position: fixed;
    top: 1rem;
    right: 1rem;
    z-index: 1000;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    max-width: min(360px, calc(100vw - 2rem));
  }

  .toast {
    display: flex;
    align-items: flex-start;
    gap: 0.5rem;
    padding: 0.6rem 0.75rem;
    border: 3px solid #1a1108;
    border-right-width: 5px;
    border-bottom-width: 5px;
    background: #f4e4bc;
    color: #1a1108;
    font-family: "Courier New", monospace;
    font-weight: bold;
    box-shadow: 3px 3px 0 rgba(0, 0, 0, 0.4);
  }

  .toast.is-notice {
    background: #b7d9a0;
  }

  .toast.is-alert {
    background: #e6a3a3;
  }

  .toast-message {
    flex: 1;
    line-height: 1.3;
  }

  .toast-close {
    flex: none;
    border: none;
    background: transparent;
    color: inherit;
    font-size: 1.1rem;
    line-height: 1;
    cursor: pointer;
    padding: 0;
  }
</style>
