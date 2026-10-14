import { Plugin } from "@opencode/plugin"
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
    const response = await fetch("https://inference-api.nousresearch.com/v1/models", {
      headers: { Authorization: `Bearer ${credential.key}` },
      signal: AbortSignal.timeout(8000),
    })
    if (!response.ok) throw new Error(`Nous model catalog returned HTTP ${response.status}`)
    const catalog = Schema.decodeUnknownSync(Catalog)(await response.json())
    const models = "data" in catalog ? catalog.data : catalog
    const free = models.filter((model) => /:free$/i.test(model.id))
    const selected = free
    await ctx.model.transform((editor) => {
      const provider = editor.provider.get("nous-portal")
      if (!provider) return
      const tag = provider.provider.settings?.nousUserTag
      const ids = new Set(selected.map((model) => model.id))
      for (const model of editor.list("nous-portal")) {
        if (!ids.has(model.id)) editor.remove("nous-portal", model.id)
      }
      for (const item of selected) {
        editor.update("nous-portal", item.id, (model) => {
          model.name = item.name ?? item.id
          if (typeof tag === "string") model.body = { ...model.body, tags: [tag] }
          if (model.settings) delete model.settings.nousUserTag
        })
      }
    })
  },
})
