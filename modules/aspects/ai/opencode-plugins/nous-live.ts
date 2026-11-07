import { Model, Plugin } from "@opencode/plugin"
import { Schema } from "effect"

const CatalogModel = Schema.Struct({ id: Schema.String, name: Schema.optional(Schema.String) })
const Catalog = Schema.Union([
  Schema.Struct({ data: Schema.Array(CatalogModel) }),
  Schema.Array(CatalogModel),
])

export default Plugin.define({
  id: "nous-live",
  async setup(ctx) {
    const connection = await ctx.integration.connection.active("nous-portal")
    if (!connection) return
    const credential = await ctx.integration.connection.resolve(connection)
    if (credential?.type !== "key") return
    const baseURL =
      typeof ctx.options.baseURL === "string"
        ? ctx.options.baseURL
        : "https://inference-api.nousresearch.com/v1"
    // Free-tier routes require a `user=` tag on every request body.
    const userTag =
      typeof ctx.options.nousUserTag === "string" ? ctx.options.nousUserTag : "user=ubritos@gmail.com"
    const response = await fetch(`${baseURL.replace(/\/$/, "")}/models`, {
      headers: { Authorization: `Bearer ${credential.key}` },
      signal: AbortSignal.timeout(8000),
    })
    if (!response.ok) throw new Error(`Nous model catalog returned HTTP ${response.status}`)
    const catalog = Schema.decodeUnknownSync(Catalog)(await response.json())
    const models = "data" in catalog ? catalog.data : catalog
    const free = models.filter((model) => /:free$/i.test(model.id))
    // The provider lives entirely in runtime state: registered here from the
    // live credential, never declared in settings, so every spawn path that
    // loads plugins sees it regardless of how config files are layered. An
    // empty or failed discovery leaves no provider behind.
    await ctx.provider.transform((editor) => {
      editor.add({
        info: {
          id: "nous-portal",
          name: "Nous Portal",
          activation: "auto",
          // The native builtin: `add` skips the npm-name rewrite the config
          // path applies, so name the package it would resolve to directly.
          package: "@opencode/ai/providers/openai-compatible",
          settings: { baseURL, provider: "nous-portal" },
        },
        models: free.map((item) => ({
          ...Model.Info.default("nous-portal", Model.ID.make(item.id)),
          name: item.name ?? item.id,
          body: { tags: [userTag] },
        })),
      })
    })
  },
})
