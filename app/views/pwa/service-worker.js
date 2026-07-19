// Kung Fu Madness service worker.
// cache-version: 2 — bump this comment on every change so browsers refetch the SW.
//
// Web Push handling only for now (no offline caching yet). Registered at root
// scope from app/javascript/push.js so it controls the whole app.

self.addEventListener("install", () => self.skipWaiting())
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()))

// A challenge push arrives as JSON: { title, body, url }. Fall back gracefully
// if a push ever arrives with no data payload.
self.addEventListener("push", (event) => {
  let data = {}
  try {
    data = event.data ? event.data.json() : {}
  } catch (e) {
    data = {}
  }

  const title = data.title || "New challenge!"
  const options = {
    body: data.body || "Someone challenges you.",
    tag: "kfm-challenge",
    data: { url: data.url || "/" }
  }

  event.waitUntil(self.registration.showNotification(title, options))
})

// Tapping the notification focuses an existing tab on that URL, or opens one.
self.addEventListener("notificationclick", (event) => {
  event.notification.close()
  const target = (event.notification.data && event.notification.data.url) || "/"

  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        const clientPath = new URL(client.url).pathname
        if (clientPath === target && "focus" in client) return client.focus()
      }
      if (self.clients.openWindow) return self.clients.openWindow(target)
    })
  )
})
