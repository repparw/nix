import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  extractEightBitdoUltimate2cFirmware,
  extractValue,
  runChangeDetection,
  stableStringify,
  validateWatchers,
} from "./change-detection.mjs";

const noop = () => {};

function fixture(t, watchers, state) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "change-detection-test-"));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const watchersPath = path.join(directory, "watchers.json");
  const statePath = path.join(directory, "state.json");
  const discordWebhookPath = path.join(directory, "webhook");
  fs.writeFileSync(watchersPath, JSON.stringify(watchers));
  fs.writeFileSync(discordWebhookPath, "https://discord.example/webhook\n");
  if (state !== undefined) fs.writeFileSync(statePath, JSON.stringify(state));
  return { directory, watchersPath, statePath, discordWebhookPath };
}

function regexWatcher(overrides = {}) {
  return {
    slug: "release",
    url: "https://release.example/page",
    mode: "regex",
    pattern: "version: (.*)",
    ...overrides,
  };
}

function response(body = "", init = {}) {
  return new Response(body, { status: 200, ...init });
}

async function waitFor(predicate, timeoutMs = 2000) {
  const deadline = Date.now() + timeoutMs;
  while (!predicate()) {
    if (Date.now() >= deadline) throw new Error("timed out waiting for condition");
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}

test("watcher validation rejects malformed, ambiguous, and unsafe configurations", () => {
  const invalidCases = [
    [[{}], /slug/],
    [[null], /must be an object/],
    [[regexWatcher({ slug: "__proto__" })], /safe/],
    [
      [regexWatcher(), regexWatcher({ url: "https://other.example" })],
      /duplicate watcher slug/,
    ],
    [[regexWatcher({ url: "file:///etc/passwd" })], /HTTP or HTTPS/],
    [[regexWatcher({ timeoutMs: 0 })], /timeoutMs/],
    [[regexWatcher({ maxResponseBytes: 0 })], /maxResponseBytes/],
    [[regexWatcher({ pattern: "(" })], /invalid regular expression/],
    [[regexWatcher({ group: -1 })], /group/],
    [[regexWatcher({ headers: { Accept: 4 } })], /must be a string/],
    [[regexWatcher({ message: 4 })], /message must be a string/],
    [[regexWatcher({ method: "" })], /method must not be empty/],
    [[regexWatcher({ mode: "unknown" })], /Unknown watcher mode/],
  ];

  for (const [value, expected] of invalidCases) {
    assert.throws(() => validateWatchers(value), expected);
  }

  assert.doesNotThrow(() =>
    validateWatchers([{ slug: "paused", enabled: false }]),
  );
});

test("extractors fail closed and handle distant firmware entries", () => {
  const farApart = [
    '<section id="ultimate-2c-wireless">',
    "<!-- Controller firmware --><h5>Firmware v1.2.3</h5>",
    "x".repeat(6000),
    "<!-- Adapter firmware --><h5>Firmware v4.5.6</h5>",
  ].join("");
  assert.deepEqual(extractEightBitdoUltimate2cFirmware(farApart), {
    controller: "1.2.3",
    adapter: "4.5.6",
  });
  assert.throws(
    () => extractEightBitdoUltimate2cFirmware('<div id="other">'),
    /Could not find/,
  );
  assert.throws(
    () =>
      extractEightBitdoUltimate2cFirmware(
        '<div class="update-log" id="ultimate-2c-wireless"><!-- Controller firmware --><h5>Firmware v1</h5><div class="update-log" id="other"><!-- Adapter firmware --><h5>Firmware v9</h5>',
      ),
    /Could not extract.*adapter/,
  );
  assert.throws(
    () => extractValue(regexWatcher({ pattern: "version: (new)?", group: 2 }), "version: new"),
    /Could not extract/,
  );
});

test("stable object keys prevent notifications caused only by property order", async (t) => {
  assert.equal(stableStringify({ b: 2, a: [1, { d: 4, c: 3 }] }), '{"a":[1,{"c":3,"d":4}],"b":2}');
  const watcher = {
    slug: "firmware",
    url: "https://firmware.example",
    mode: "extractor",
    extractor: "eightBitdoUltimate2cFirmware",
    displayTemplate: "8bitdoFirmware",
  };
  const files = fixture(t, [watcher], {
    watchers: {
      firmware: {
        current: { adapter: "2", controller: "1" },
        currentKey: '{"adapter":"2","controller":"1"}',
      },
    },
  });
  let calls = 0;
  await runChangeDetection({
    ...files,
    fetchImpl: async () => {
      calls += 1;
      return response(
        '<div id="ultimate-2c-wireless"><!-- Controller firmware --><h5>Firmware v1</h5><!-- Adapter firmware --><h5>Firmware v2</h5>',
      );
    },
    log: noop,
  });
  assert.equal(calls, 1, "an unchanged value must not call the webhook");
});

test("initial state is atomic, private, and does not notify", async (t) => {
  const files = fixture(t, [regexWatcher()]);
  let calls = 0;
  const state = await runChangeDetection({
    ...files,
    fetchImpl: async () => {
      calls += 1;
      return response("version: 1.0");
    },
    now: () => new Date("2026-01-02T03:04:05.000Z"),
    log: noop,
  });

  assert.equal(calls, 1);
  assert.equal(state.watchers.release.current, "1.0");
  assert.equal(state.watchers.release.checkedAt, "2026-01-02T03:04:05.000Z");
  assert.equal(fs.statSync(files.statePath).mode & 0o777, 0o600);
  assert.deepEqual(
    fs.readdirSync(files.directory).filter((name) => name.includes(".tmp") || name.endsWith(".lock")),
    [],
  );
});

test("an empty previous value is still a value and triggers a change", async (t) => {
  const files = fixture(t, [regexWatcher()], {
    watchers: { release: { current: "", currentKey: "", displayValue: "" } },
  });
  const posts = [];
  await runChangeDetection({
    ...files,
    fetchImpl: async (url, options = {}) => {
      if (options.method === "POST") {
        posts.push(JSON.parse(options.body));
        return response();
      }
      return response("version: populated");
    },
    log: noop,
  });
  assert.equal(posts.length, 1);
  assert.match(posts[0].content, /changed:  -> populated/);
});

test("legacy state participates in comparisons and template values are literal", async (t) => {
  const watcher = regexWatcher({ message: "{{previous}} => {{current}} @ {{url}}" });
  const files = fixture(t, [watcher], {
    watchers: { release: { current: "$&-old" } },
  });
  let content;
  await runChangeDetection({
    ...files,
    fetchImpl: async (_url, options = {}) => {
      if (options.method === "POST") {
        content = JSON.parse(options.body).content;
        return response();
      }
      return response("version: $`-$&-$'-new");
    },
    log: noop,
  });
  assert.equal(
    content,
    "$&-old => $`-$&-$'-new @ https://release.example/page",
  );
});

test("oversized responses are rejected from both declared and streamed sizes", async (t) => {
  const watcher = regexWatcher({ maxResponseBytes: 8 });
  const files = fixture(t, [watcher]);
  await assert.rejects(
    runChangeDetection({
      ...files,
      fetchImpl: async () =>
        response("short", { headers: { "content-length": "9" } }),
      log: noop,
    }),
    /response exceeds 8 bytes/,
  );
  await assert.rejects(
    runChangeDetection({
      ...files,
      fetchImpl: async () => response("version: too large"),
      log: noop,
    }),
    /response exceeds 8 bytes/,
  );
});

test("malformed state is preserved and does not strand the lock", async (t) => {
  const files = fixture(t, [regexWatcher()]);
  fs.writeFileSync(files.statePath, "[]\n");
  const run = () =>
    runChangeDetection({
      ...files,
      fetchImpl: async () => response("version: 1"),
      log: noop,
    });
  await assert.rejects(run(), /state file must contain/);
  await assert.rejects(run(), /state file must contain/);
  assert.equal(fs.readFileSync(files.statePath, "utf8"), "[]\n");
  assert.equal(fs.existsSync(`${files.statePath}.lock`), false);
});

test("bounded local files and fetch timeouts fail without corrupting state", async (t) => {
  const files = fixture(t, [regexWatcher({ timeoutMs: 10 })]);
  fs.writeFileSync(files.watchersPath, " ".repeat(1024 * 1024 + 1));
  await assert.rejects(
    runChangeDetection({
      ...files,
      fetchImpl: async () => response("version: 1"),
      log: noop,
    }),
    /watchers config exceeds/,
  );

  fs.writeFileSync(files.watchersPath, JSON.stringify([regexWatcher({ timeoutMs: 10 })]));
  await assert.rejects(
    runChangeDetection({
      ...files,
      fetchImpl: async (_url, { signal }) =>
        new Promise((_resolve, reject) => {
          signal.addEventListener("abort", () => reject(signal.reason), {
            once: true,
          });
        }),
      log: noop,
    }),
    /aborted/i,
  );
  assert.equal(fs.existsSync(`${files.statePath}.lock`), false);
  assert.equal(fs.existsSync(files.statePath), false);
});

test("concurrent invocations cannot race state updates", async (t) => {
  const files = fixture(t, [regexWatcher()]);
  let releaseFetch;
  let fetchStarted;
  const started = new Promise((resolve) => {
    fetchStarted = resolve;
  });
  const first = runChangeDetection({
    ...files,
    fetchImpl: async () => {
      fetchStarted();
      await new Promise((resolve) => {
        releaseFetch = resolve;
      });
      return response("version: 1");
    },
    log: noop,
  });
  await started;
  await assert.rejects(
    runChangeDetection({
      ...files,
      fetchImpl: async () => response("version: 2"),
      log: noop,
    }),
    /already locked/,
  );
  releaseFetch();
  await first;
  assert.equal(JSON.parse(fs.readFileSync(files.statePath)).watchers.release.current, "1");
});

test("termination releases the state lock", async (t) => {
  const files = fixture(t, [regexWatcher()]);
  const moduleUrl = new URL("./change-detection.mjs", import.meta.url).href;
  const program = `
    import { runChangeDetection } from ${JSON.stringify(moduleUrl)};
    await runChangeDetection({
      watchersPath: ${JSON.stringify(files.watchersPath)},
      statePath: ${JSON.stringify(files.statePath)},
      discordWebhookPath: ${JSON.stringify(files.discordWebhookPath)},
      fetchImpl: async () => new Promise(() => {}),
      handleSignals: true,
    });
  `;
  const child = spawn(
    process.execPath,
    ["--input-type=module", "--eval", program],
    { stdio: "ignore" },
  );
  t.after(() => {
    if (child.exitCode === null) child.kill("SIGKILL");
  });
  await waitFor(() => fs.existsSync(`${files.statePath}.lock`));
  child.kill("SIGTERM");
  const result = await new Promise((resolve) => {
    child.once("exit", (code, signal) => resolve({ code, signal }));
  });
  assert.deepEqual(result, { code: 143, signal: null });
  assert.equal(fs.existsSync(`${files.statePath}.lock`), false);
});

test("failed fetches and notifications never commit partial state", async (t) => {
  const watchers = [regexWatcher({ slug: "first" }), regexWatcher({ slug: "second" })];
  const files = fixture(t, watchers, { watchers: {} });
  let request = 0;
  await assert.rejects(
    runChangeDetection({
      ...files,
      fetchImpl: async () => {
        request += 1;
        return request === 1 ? response("version: 1") : response("failure", { status: 500 });
      },
      log: noop,
    }),
    /second returned HTTP 500/,
  );
  assert.deepEqual(JSON.parse(fs.readFileSync(files.statePath)), { watchers: {} });

  const changedFiles = fixture(t, [regexWatcher()], {
    watchers: { release: { current: "old", currentKey: "old" } },
  });
  await assert.rejects(
    runChangeDetection({
      ...changedFiles,
      fetchImpl: async (_url, options = {}) =>
        options.method === "POST"
          ? response("failure", { status: 503 })
          : response("version: new"),
      log: noop,
    }),
    /webhook returned HTTP 503/,
  );
  assert.equal(
    JSON.parse(fs.readFileSync(changedFiles.statePath)).watchers.release.current,
    "old",
  );
});
