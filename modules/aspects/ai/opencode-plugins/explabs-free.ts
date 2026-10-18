import { Model, Plugin, Provider } from "@opencode/plugin"
import { Schema } from "effect"

const Catalog = Schema.Struct({
  data: Schema.Array(Schema.Struct({ id: Schema.String, canonical_slug: Schema.optional(Schema.String) })),
})
const Detail = Schema.Struct({
  model: Schema.Struct({
    context_window: Schema.NullOr(Schema.Int),
    max_output_tokens: Schema.NullOr(Schema.Int),
    input_modalities: Schema.Array(Schema.String),
    output_modalities: Schema.Array(Schema.String),
  }),
  default_waterfall: Schema.Array(Schema.Struct({ position: Schema.Int, model_provider_id: Schema.String })),
  providers: Schema.Array(Schema.Struct({
    id: Schema.String,
    input_nano_usd_per_million: Schema.NullOr(Schema.Finite),
    output_nano_usd_per_million: Schema.NullOr(Schema.Finite),
    capabilities: Schema.Struct({ supports_tools: Schema.Boolean, supports_streaming: Schema.Boolean }),
  })),
})
const providerID = Provider.ID.make("explabs")

export default Plugin.define({
  id: "explabs-free",
  async setup(ctx) {
    // An empty or failed discovery must not reuse a previous inventory.
    await ctx.provider.transform((editor) => editor.models.set(providerID, []))
    const connection = await ctx.integration.connection.active(providerID)
    if (!connection) return
    const credential = await ctx.integration.connection.resolve(connection)
    if (credential?.type !== "key") return
    const configured = typeof ctx.options.baseURL === "string"
      ? ctx.options.baseURL : "https://api.experientiallabs.ai/api/v1"
    const catalogURL = `${configured.replace(/\/$/, "")}/models`
    const origin = new URL(configured).origin

    const headers = { Authorization: `Bearer ${credential.key}` }
    const get = async (url: string) => {
      const response = await fetch(url, { headers, redirect: "error", signal: AbortSignal.timeout(8000) })
      if (!response.ok) throw new Error(`Experiential Labs catalog returned HTTP ${response.status}`)
      return response.json()
    }
    const catalog = Schema.decodeUnknownSync(Catalog)(
      await get(catalogURL),
    )
    const models = await Promise.all(catalog.data.filter((item) => item.id.endsWith(":free")).map(async (item) => {
      const slug = (item.canonical_slug ?? item.id.split("/").at(-1) ?? item.id).replace(/:free$/, "")
      const detail = Schema.decodeUnknownSync(Detail)(
        await get(`${origin}/api/models/${encodeURIComponent(slug)}`),
      )
      const first = detail.default_waterfall.find((entry) => entry.position === 0)
      const route = detail.providers.find((entry) => entry.id === first?.model_provider_id)
      const { context_window: context, max_output_tokens: output } = detail.model
      if (!route?.capabilities.supports_tools || !route.capabilities.supports_streaming ||
          context === null || output === null || context <= 0 || output <= 0 ||
          route.input_nano_usd_per_million === null || route.output_nano_usd_per_million === null) return []
      const model = Model.Info.default(providerID, Model.ID.make(item.id))
      return [{
        ...model,
        name: item.id,
        limit: { context, output },
        capabilities: { tools: true, input: [...detail.model.input_modalities], output: [...detail.model.output_modalities] },
        cost: [Schema.decodeUnknownSync(Model.Cost)({
          input: route.input_nano_usd_per_million / 1e9,
          output: route.output_nano_usd_per_million / 1e9,
          cache: { read: 0, write: 0 },
        })],
      }]
    }))
    // Preserve :free in the request ID: never substitute a paid canonical slug.
    await ctx.provider.transform((editor) => editor.models.set(providerID, models.flat()))
  },
})
