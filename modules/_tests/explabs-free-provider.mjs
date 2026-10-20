// Exercise the installed OpenCode plugin host with a local gateway fixture.
import assert from "node:assert/strict"
import { spawn } from "node:child_process"
import { mkdtemp, mkdir, writeFile, copyFile, rm } from "node:fs/promises"
import { createServer } from "node:http"
import { tmpdir } from "node:os"
import { join, resolve } from "node:path"

const [binary, plugin] = process.argv.slice(2)
assert(binary && plugin, "usage: node explabs-free-provider.mjs OPENCODE PLUGIN")
const root = await mkdtemp(join(tmpdir(), "explabs-free-"))
let catalog = { data: [] }
let status = 200
const requests = []
const completions = []
const detail = {
  model: { context_window: 65536, max_output_tokens: 4096, input_modalities: ["text"], output_modalities: ["text"] },
  default_waterfall: [{ position: 1, model_provider_id: "other" }, { position: 0, model_provider_id: "default" }],
  providers: [{ id: "default", input_nano_usd_per_million: 100000000, output_nano_usd_per_million: 200000000,
    capabilities: { supports_tools: true, supports_streaming: true } }],
}
const server = createServer(async (request, response) => {
  requests.push(request.url)
  assert.equal(request.headers.authorization, "Bearer fixture-key")
  if (request.url === "/api/v1/chat/completions") {
    let body = ""
    for await (const chunk of request) body += chunk
    const input = JSON.parse(body)
    completions.push(input.model)
    assert(input.model.endsWith(":free"), "A request reached a paid model")
    response.writeHead(200, { "Content-Type": "text/event-stream" })
    const chunk = (delta, finish_reason = null) => `data: ${JSON.stringify({
      id: "chatcmpl-fixture", object: "chat.completion.chunk", created: 1, model: input.model,
      choices: [{ index: 0, delta, finish_reason }],
    })}\n\n`
    response.end(chunk({ role: "assistant", content: "ok" }) + chunk({}, "stop") + "data: [DONE]\n\n")
    return
  }
  response.writeHead(status, { "Content-Type": "application/json" })
  response.end(JSON.stringify(request.url === "/api/v1/models" ? catalog : detail))
})
await new Promise((done) => server.listen(0, "127.0.0.1", done))
const address = server.address()
assert(address && typeof address === "object")
const config = join(root, "config/opencode")
await mkdir(config, { recursive: true })
const pluginDirectory = join(root, "fixture-plugin")
await mkdir(pluginDirectory)
await copyFile(resolve(plugin), join(pluginDirectory, "index.ts"))
await writeFile(join(config, "opencode.json"), JSON.stringify({
  plugins: [{ package: pluginDirectory, options: { baseURL: `http://127.0.0.1:${address.port}/api/v1` } }],
  provider: { explabs: { npm: "@ai-sdk/openai-compatible", name: "Experiential Labs",
    options: { baseURL: `http://127.0.0.1:${address.port}/api/v1` } } },
}))
const env = { ...process.env, HOME: root, XDG_CONFIG_HOME: join(root, "config"),
  XDG_DATA_HOME: join(root, "data"), XDG_STATE_HOME: join(root, "state"), XDG_CACHE_HOME: join(root, "cache"),
  OPENCODE_DISABLE_MODELS_FETCH: "true" }
delete env.OPENCODE_CONFIG
delete env.OPENCODE_CONFIG_CONTENT
delete env.OPENCODE_CONFIG_DIR

function run(args, input = "") {
  return new Promise((done, reject) => {
    const child = spawn(binary, args, { cwd: root, env, stdio: ["pipe", "pipe", "pipe"] })
    let stdout = "", stderr = ""
    const timeout = setTimeout(() => { child.kill("SIGKILL"); reject(new Error("OpenCode timed out")) }, 45000)
    child.stdout.on("data", (data) => { stdout += data })
    child.stderr.on("data", (data) => { stderr += data })
    child.on("error", reject)
    child.on("close", (code) => {
      clearTimeout(timeout)
      done({ stdout, stderr, code })
    })
    child.stdin.end(input)
  })
}

try {
  const imported = await run(["auth", "import", "--standalone"], JSON.stringify([{
    id: "cred_explabs_fixture", integrationID: "explabs", label: "test", active: true,
    value: { type: "key", key: "fixture-key" },
  }]))
  assert.equal(imported.code, 0, imported.stderr)
  const attempt = (id) => run(["run", "--standalone", "--format", "json", "--model", `explabs/${id}`, "Reply ok"])
  catalog = { data: [{ id: "vendor/one:free", canonical_slug: "one" }, { id: "vendor/paid" }] }
  const first = await attempt("vendor/one:free")
  assert.equal(first.code, 0, JSON.stringify({ first, requests }))
  assert(completions.includes("vendor/one:free"), JSON.stringify({ first, requests }))
  assert(requests.includes("/api/models/one"))
  assert(!requests.includes("/api/models/paid"))
  catalog = { data: [{ id: "vendor/new:free", canonical_slug: "new" }] }
  const refreshed = await attempt("vendor/new:free")
  assert.equal(refreshed.code, 0, refreshed.stderr + refreshed.stdout)
  assert(completions.includes("vendor/new:free"))
  const completed = completions.length
  catalog = { data: [] }
  await attempt("vendor/one:free")
  assert.equal(completions.length, completed)
  await attempt("vendor/paid")
  assert.equal(completions.length, completed)
  status = 503
  await attempt("vendor/one:free")
  assert.equal(completions.length, completed)
  status = 200
  catalog = { data: [{ id: "vendor/decision:free", canonical_slug: "decision" }] }
  detail.providers[0].capabilities.supports_tools = false
  await attempt("vendor/decision:free")
  assert.equal(completions.length, completed)
  console.log("PASS: free-only discovery, refresh/removal, empty catalog, outage, and decision exclusion")
} finally {
  server.closeAllConnections()
  server.close()
  if (process.env.EXPLABS_KEEP_TEST_ROOT) console.error(root)
  else await rm(root, { recursive: true, force: true })
}
