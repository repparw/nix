// Exercise the installed OpenCode plugin host with a local OrcaRouter fixture.
// Proves both live-state plugins: the provider is registered purely by the
// orca-router plugin (no provider in any config file), and the session
// default model comes from the model-defaults plugin (no `model` key).
import assert from "node:assert/strict"
import { spawn } from "node:child_process"
import { mkdtemp, mkdir, writeFile, copyFile, rm } from "node:fs/promises"
import { createServer } from "node:http"
import { tmpdir } from "node:os"
import { join, resolve } from "node:path"

const [binary, orcaPlugin, defaultsPlugin] = process.argv.slice(2)
assert(binary && orcaPlugin && defaultsPlugin, "usage: node orca-live-provider.mjs OPENCODE ORCA_PLUGIN DEFAULTS_PLUGIN")
const root = await mkdtemp(join(tmpdir(), "orca-live-"))
const completions = []
const server = createServer(async (request, response) => {
  if (request.url === "/v1/chat/completions") {
    let body = ""
    for await (const chunk of request) body += chunk
    const input = JSON.parse(body)
    completions.push(input.model)
    response.writeHead(200, { "Content-Type": "text/event-stream" })
    const chunk = (delta, finish_reason = null) => `data: ${JSON.stringify({
      id: "chatcmpl-fixture", object: "chat.completion.chunk", created: 1, model: input.model,
      choices: [{ index: 0, delta, finish_reason }],
    })}\n\n`
    response.end(chunk({ role: "assistant", content: "ok" }) + chunk({}, "stop") + "data: [DONE]\n\n")
    return
  }
  response.writeHead(200, { "Content-Type": "application/json" })
  response.end("{}")
})
await new Promise((done) => server.listen(0, "127.0.0.1", done))
const address = server.address()
assert(address && typeof address === "object")
const config = join(root, "config/opencode")
await mkdir(config, { recursive: true })
const orcaDirectory = join(root, "orca-plugin")
const defaultsDirectory = join(root, "defaults-plugin")
await mkdir(orcaDirectory)
await mkdir(defaultsDirectory)
await copyFile(resolve(orcaPlugin), join(orcaDirectory, "index.ts"))
await copyFile(resolve(defaultsPlugin), join(defaultsDirectory, "index.ts"))
// Deliberately no `provider` and no `model` key: both must come from plugins.
await writeFile(join(config, "opencode.json"), JSON.stringify({
  plugins: [
    { package: orcaDirectory, options: { baseURL: `http://127.0.0.1:${address.port}/v1` } },
    // Point the default at the fixture-backed provider so the assertion
    // cannot pass through opencode's built-in fallback default.
    { package: defaultsDirectory, options: { model: "orcarouter/deepseek/deepseek-v4-flash-free" } },
  ],
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
  const attempt = (args) => run(["run", "--standalone", "--format", "json", ...args, "Reply ok"])
  // No --model: the session default must come from the model-defaults plugin.
  const defaulted = await attempt([])
  assert.equal(defaulted.code, 0, JSON.stringify({ defaulted, completions }))
  assert(completions.includes("deepseek/deepseek-v4-flash-free"), JSON.stringify({ defaulted, completions }))
  // An unregistered model stays unreachable.
  const absent = await attempt(["--model", "orcarouter/not-in-catalog"])
  assert.notEqual(absent.code, 0, JSON.stringify({ absent, completions }))
  assert(!completions.includes("not-in-catalog"), JSON.stringify({ completions }))
  console.log("PASS: live provider registration and plugin-set session default model")
} finally {
  server.closeAllConnections()
  server.close()
  if (process.env.ORCA_KEEP_TEST_ROOT) console.error(root)
  else await rm(root, { recursive: true, force: true })
}
