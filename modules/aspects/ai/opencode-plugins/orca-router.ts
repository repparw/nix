import { Model, Plugin } from "@opencode/plugin"

const MODELS = [
  { id: "deepseek/deepseek-v4-flash-free", name: "DeepSeek V4 Flash (Free)" },
  { id: "deepseek/deepseek-v4-pro-free", name: "DeepSeek V4 Pro (Free)" },
]

export default Plugin.define({
  id: "orca-router",
  async setup(ctx) {
    const baseURL =
      typeof ctx.options.baseURL === "string" ? ctx.options.baseURL : "https://api.orcarouter.ai/v1"
    // Static catalog: registered from runtime state like the other live
    // providers, never declared in settings, so every spawn path that loads
    // plugins sees it regardless of how config files are layered.
    await ctx.provider.transform((editor) => {
      editor.add({
        info: {
          id: "orcarouter",
          name: "OrcaRouter",
          activation: "enabled",
          // The native builtin: `add` skips the npm-name rewrite the config
          // path applies, so name the package it would resolve to directly.
          package: "@opencode/ai/providers/openai-compatible",
          settings: { baseURL, provider: "orcarouter" },
        },
        models: MODELS.map((item) => ({
          ...Model.Info.default("orcarouter", Model.ID.make(item.id)),
          name: item.name,
        })),
      })
    })
  },
})
