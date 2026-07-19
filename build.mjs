import * as esbuild from "esbuild"
import sveltePlugin from "esbuild-svelte"

const watch = process.argv.includes("--watch")
const minify = process.argv.includes("--minify")

// css: "injected" ships each component's <style> block inside the bundle and
// mounts it at runtime, so Svelte style blocks work here while the sass
// pipeline stays the sole writer of app/assets/builds/application.css.
const options = {
  entryPoints: ["app/javascript/application.js"],
  bundle: true,
  format: "esm",
  sourcemap: true,
  minify,
  outdir: "app/assets/builds",
  conditions: ["svelte", "browser"],
  plugins: [sveltePlugin({ compilerOptions: { css: "injected" } })],
  logLevel: "info",
}

if (watch) {
  const context = await esbuild.context(options)
  await context.watch()
} else {
  await esbuild.build(options)
}
