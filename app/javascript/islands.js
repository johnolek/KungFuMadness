// Svelte islands over server-rendered pages: any element with
// data-svelte-component mounts the named component with data-props as its
// props. Mounted on every Turbo visit; unmounted before Turbo caches the page
// so restored snapshots hold an empty root and remount cleanly.
import { mount, unmount } from "svelte"
import DojoPlaceholder from "./components/DojoPlaceholder.svelte"
import Toasts from "./components/Toasts.svelte"
import MoveCommitter from "./components/MoveCommitter.svelte"
import FightPlayback from "./components/FightPlayback.svelte"
import RecentFightsSidebar from "./components/RecentFightsSidebar.svelte"
import OnlineSidebar from "./components/OnlineSidebar.svelte"
import Inbox from "./components/Inbox.svelte"
import ChallengeModal from "./components/ChallengeModal.svelte"
import MatchHistory from "./components/MatchHistory.svelte"
import NavBadges from "./components/NavBadges.svelte"

const registry = {
  DojoPlaceholder,
  Toasts,
  MoveCommitter,
  FightPlayback,
  RecentFightsSidebar,
  OnlineSidebar,
  Inbox,
  ChallengeModal,
  MatchHistory,
  NavBadges,
}
const active = new Map()

function mountIslands() {
  for (const el of document.querySelectorAll("[data-svelte-component]")) {
    if (active.has(el)) continue
    const Component = registry[el.dataset.svelteComponent]
    if (!Component) continue
    const props = el.dataset.props ? JSON.parse(el.dataset.props) : {}
    active.set(el, mount(Component, { target: el, props }))
  }
}

function unmountIslands() {
  for (const instance of active.values()) unmount(instance)
  active.clear()
}

document.addEventListener("turbo:load", mountIslands)
document.addEventListener("turbo:before-cache", unmountIslands)
