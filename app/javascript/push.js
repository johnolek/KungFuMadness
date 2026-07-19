// Progressive opt-in for Web Push challenge alerts. Enhances a server-rendered
// panel ([data-push-alerts]) the same way live.js enhances plain buttons: no
// island, just data attributes wired to the browser's Push API. Hidden entirely
// when the browser can't do push, or when the server didn't emit a VAPID key.

const SUPPORTED =
  typeof window !== "undefined" &&
  "serviceWorker" in navigator &&
  "PushManager" in window &&
  "Notification" in window

let registration = null

function metaContent(name) {
  return document.querySelector(`meta[name="${name}"]`)?.content || ""
}

// VAPID public key (base64url) → the Uint8Array pushManager wants.
function urlBase64ToUint8Array(base64) {
  const padding = "=".repeat((4 - (base64.length % 4)) % 4)
  const normalized = (base64 + padding).replace(/-/g, "+").replace(/_/g, "/")
  const raw = atob(normalized)
  return Uint8Array.from([...raw].map((c) => c.charCodeAt(0)))
}

async function ensureRegistration() {
  if (registration) return registration
  registration = await navigator.serviceWorker.register("/service-worker")
  return registration
}

async function postSubscription(subscription) {
  await fetch("/push_subscriptions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      "X-CSRF-Token": metaContent("csrf-token")
    },
    body: JSON.stringify(subscription)
  })
}

async function deleteSubscription(endpoint) {
  await fetch("/push_subscriptions", {
    method: "DELETE",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      "X-CSRF-Token": metaContent("csrf-token")
    },
    body: JSON.stringify({ endpoint })
  })
}

function render(panel, state) {
  const status = panel.querySelector("[data-push-status]")
  const enable = panel.querySelector("[data-push-enable]")
  const disable = panel.querySelector("[data-push-disable]")

  const messages = {
    on: "Notifications on — you'll be pinged when someone challenges you.",
    off: "Get a notification the moment someone challenges you.",
    blocked: "Notifications are blocked in your browser settings.",
    working: "Working…"
  }
  if (status) status.textContent = messages[state] || messages.off
  if (enable) enable.hidden = state !== "off"
  if (disable) disable.hidden = state !== "on"
}

async function enable(panel) {
  render(panel, "working")
  const permission = await Notification.requestPermission()
  if (permission !== "granted") {
    render(panel, permission === "denied" ? "blocked" : "off")
    return
  }

  const key = metaContent("vapid-public-key")
  if (!key) {
    render(panel, "off")
    return
  }

  const reg = await ensureRegistration()
  const subscription = await reg.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: urlBase64ToUint8Array(key)
  })
  await postSubscription(subscription.toJSON())
  render(panel, "on")
}

async function disable(panel) {
  render(panel, "working")
  const reg = await ensureRegistration()
  const subscription = await reg.pushManager.getSubscription()
  if (subscription) {
    await deleteSubscription(subscription.endpoint)
    await subscription.unsubscribe()
  }
  render(panel, "off")
}

async function initPanel() {
  const panel = document.querySelector("[data-push-alerts]")
  if (!panel) return
  if (!SUPPORTED || Notification.permission === "denied") {
    if (SUPPORTED && Notification.permission === "denied") {
      panel.hidden = false
      render(panel, "blocked")
    }
    return
  }

  panel.hidden = false

  const enableBtn = panel.querySelector("[data-push-enable]")
  const disableBtn = panel.querySelector("[data-push-disable]")
  enableBtn?.addEventListener("click", () => enable(panel).catch(() => render(panel, "off")))
  disableBtn?.addEventListener("click", () => disable(panel).catch(() => render(panel, "on")))

  try {
    const reg = await ensureRegistration()
    const subscription = await reg.pushManager.getSubscription()
    render(panel, subscription ? "on" : "off")
  } catch (e) {
    render(panel, "off")
  }
}

document.addEventListener("turbo:load", initPanel)
if (document.readyState !== "loading") initPanel()
else document.addEventListener("DOMContentLoaded", initPanel)
