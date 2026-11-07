// Exercise the installed OpenCode plugin host with a local Nous Portal fixture.
// Proves the provider is registered purely from plugin runtime state: no
// provider declaration in any config file.
import assert from "node:assert/strict"
import { spawn } from "node:child_process"
import { mkdtemp, mkdir, writeFile, copyFile, rm } from "node:fs/promises"
import { createServer } from "node:http"
import { tmpdir } from "node:os"
import { join, resolve } from "node:path"

const [binary, plugin] = process.argv.slice(2)
assert(binary && plugin, "usage: node nous-live-provider.mjs OPENCODE PLUGIN")
const root = await mkdtemp(join(tmpdir(), "nous-live-"))
let catalog = { data: [] }
const requests = []
const completions = []
const server = createServer(async (request, response) => {
  requests.push(request.url)
  assert.equal(request.headers.authorization, "Bearer fixture-key")
  if (request.url === "/v1/chat/completions") {
    let body = ""
    for await (const chunk of request) body += chunk
    const input = JSON.parse(body)
    completions.push({ model: input.model, tags: input.tags })
    assert(input.model.endsWith(":free"), "A request reached a paid model")
    response.writeHead(200, { "Content-Type": "text/event-stream" })
    const chunk = (delta, finish_reason = null) => `data: ${JSON.stringify({
      id: "chatcmpl-fixture", object: "chat.completion.chunk", created: 1, model: input.model,
      choices: [{ index: 0, delta, finish_reason }],
    })}\n\n`
    response.end(chunk({ role: "assistant", content: "ok" }) + chunk({}, "stop") + "data: [DONE]\n\n")
    return
  }
  response.writeHead(200, { "Content-Type": "application/json" })
  response.end(JSON.stringify(request.url === "/v1/models" ? catalog : {}))
})
await new Promise((done) => server.listen(0, "127.0.0.1", done))
const address = server.address()
assert(address && typeof address === "object")
const config = join(root, "config/opencode")
await mkdir(config, { recursive: true })
const pluginDirectory = join(root, "fixture-plugin")
await mkdir(pluginDirectory)
await copyFile(resolve(plugin), join(pluginDirectory, "index.ts"))
// Deliberately no `provider` block: nous-portal must exist only through the plugin.
await writeFile(join(config, "opencode.json"), JSON.stringify({
  plugins: [{ package: pluginDirectory, options: { baseURL: `http://127.0.0.1:${address.port}/v1`, nousUserTag: "user=fixture" } }],
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
    id: "cred_nous_fixture", integrationID: "nous-portal", label: "test", active: true,
    value: { type: "key", key: "fixture-key" },
  }]))
  assert.equal(imported.code, 0, imported.stderr)
  const catalogOne = { data: [{ id: "vendor/one:free", name: "One Free" }, { id: "vendor/paid", name: "Paid" }] }
  catalog = catalogOne
  const attempt = (id) => run(["run", "--standalone", "--format", "json", "--model", `nous-portal/${id}`, "Reply ok"])
  const first = await attempt("vendor/one:free")
  assert.equal(first.code, 0, JSON.stringify({ first, requests }))
  assert(completions.some((entry) => entry.model === "vendor/one:free"), JSON.stringify({ first, requests }))
  assert(completions.every((entry) => entry.tags === undefined || entry.tags.includes("user=fixture")),
    JSON.stringify(completions))
  // A paid catalog entry must not surface as a selectable model.
  const beforePaid = completions.length
  const paid = await attempt("vendor/paid")
  assert.notEqual(paid.code, 0, JSON.stringify({ paid, requests }))
  assert.equal(completions.length, beforePaid, JSON.stringify({ completions, requests }))
  // An empty discovery leaves no provider: even the free model disappears.
  const beforeEmpty = completions.length
  catalog = { data: [] }
  const emptied = await attempt("vendor/one:free")
  assert.notEqual(emptied.code, 0, JSON.stringify({ emptied, requests }))
  assert.equal(completions.length, beforeEmpty, JSON.stringify({ completions, requests }))
  console.log("PASS: live-state provider registration, free-only catalog, tag injection, empty-discovery removal")
} finally {
  server.closeAllConnections()
  server.close()
  if (process.env.NOUS_KEEP_TEST_ROOT) console.error(root)
  else await rm(root, { recursive: true, force: true })
}
