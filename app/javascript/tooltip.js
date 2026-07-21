// Svelte action wrapping tippy.js: `use:tooltip={{ content, enabled }}`.
// Styling lives in the global sass (.tippy-box) rather than tippy's own CSS,
// so the tip matches the retro theme; duration 0 skips the CSS-dependent fade.
import tippy from "tippy.js"

export function tooltip(node, params) {
  const instance = tippy(node, {
    content: params.content,
    duration: 0,
    arrow: false,
    touch: ["hold", 300]
  })
  if (params.enabled === false) instance.disable()

  return {
    update(next) {
      instance.setContent(next.content)
      next.enabled === false ? instance.disable() : instance.enable()
    },
    destroy() {
      instance.destroy()
    }
  }
}
