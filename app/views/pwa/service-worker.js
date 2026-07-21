// Kung Fu Madness service worker.
// cache-version: 3 — bump CACHE_NAME on every change so browsers refetch the SW.
//
// Registered at root scope from app/javascript/push.js so it controls the
// whole app. Handles Web Push and a minimal offline fallback: navigations go
// network-first and fall back to a cached /offline.html when the dojo is
// unreachable. No other requests are intercepted.

const CACHE_NAME = "kfm-v3"
const OFFLINE_URL = "/offline.html"
const PRECACHE = [OFFLINE_URL, "/icon-192.png"]

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(PRECACHE)).then(() => self.skipWaiting())
  )
})

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((names) => Promise.all(names.filter((n) => n !== CACHE_NAME).map((n) => caches.delete(n))))
      .then(() => self.clients.claim())
  )
})

self.addEventListener("fetch", (event) => {
  if (event.request.mode !== "navigate") return

  event.respondWith(
    fetch(event.request).catch(() =>
      caches.match(OFFLINE_URL).then((cached) => cached || Response.error())
    )
  )
})

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
    icon: "/icon-192.png",
    badge: "/badge.png",
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
