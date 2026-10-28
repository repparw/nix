import { Model, Plugin, Provider } from "@opencode/plugin"
import { Schema } from "effect"

const Catalog = Schema.Struct({
  data: Schema.Array(
    Schema.Struct({
      id: Schema.String,
      name: Schema.optional(Schema.String),
    }),
  ),
})

const providerID = Provider.ID.make("orcarouter")

// The /models endpoint is public, so discovery runs with or without a
// stored credential; a key is attached when one is available.
export default Plugin.define({
  id: "orcarouter-free",
  async setup(ctx) {
    // An empty or failed discovery must not reuse a previous inventory.
    await ctx.provider.transform((editor) => editor.models.set(providerID, []))
    const configured =
      typeof ctx.options.baseURL === "string"
        ? ctx.options.baseURL
        : "https://api.orcarouter.ai/v1"
    const catalogURL = `${configured.replace(/\/$/, "")}/models`

    const headers: Record<string, string> = {}
    try {
      const connection = await ctx.integration.connection.active(providerID)
      const credential = connection
        ? await ctx.integration.connection.resolve(connection)
        : null
      if (credential?.type === "key") {
        headers.Authorization = `Bearer ${credential.key}`
      }
    } catch {
      // Keyless discovery is fine; inference still needs its own auth.
    }

    const response = await fetch(catalogURL, {
      headers,
      redirect: "error",
      signal: AbortSignal.timeout(8000),
    })
    if (!response.ok) throw new Error(`OrcaRouter catalog returned HTTP ${response.status}`)
    const catalog = Schema.decodeUnknownSync(Catalog)(await response.json())
    const free = catalog.data.filter((model) => /free/i.test(model.id))
    const models = free.map((item) => {
      const model = Model.Info.default(providerID, Model.ID.make(item.id))
      return { ...model, name: item.name ?? item.id }
    })
    await ctx.provider.transform((editor) => editor.models.set(providerID, models))
  },
})
