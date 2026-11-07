import { Plugin } from "@opencode/plugin"

export default Plugin.define({
  id: "model-defaults",
  async setup(ctx) {
    const model =
      typeof ctx.options.model === "string" ? ctx.options.model : "opencode/muse-spark-1.3-contributor-free"
    const index = model.indexOf("/")
    if (index <= 0) return
    const providerID = model.slice(0, index)
    const modelID = model.slice(index + 1)
    // The session default model is runtime state: set here instead of the
    // settings file, so it applies in every spawn path that loads plugins.
    // A missing model falls back to opencode's own first-available choice.
    await ctx.model.transform((editor) => {
      editor.default.set(providerID, modelID)
    })
  },
})
