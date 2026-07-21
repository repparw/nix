import { randomUUID } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const MAX_WATCHERS_FILE_BYTES = 1024 * 1024;
const MAX_STATE_FILE_BYTES = 8 * 1024 * 1024;
const MAX_WEBHOOK_FILE_BYTES = 16 * 1024;
const DEFAULT_MAX_RESPONSE_BYTES = 2 * 1024 * 1024;
const MAX_RESPONSE_BYTES = 16 * 1024 * 1024;
const MAX_WATCHERS = 1000;

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function readUtf8File(file, maxBytes, label) {
  const descriptor = fs.openSync(file, "r");
  const chunks = [];
  let total = 0;
  try {
    while (true) {
      const chunk = Buffer.allocUnsafe(Math.min(64 * 1024, maxBytes + 1 - total));
      const bytesRead = fs.readSync(descriptor, chunk, 0, chunk.length, null);
      if (bytesRead === 0) break;
      total += bytesRead;
      if (total > maxBytes) {
        throw new Error(`${label} exceeds ${maxBytes} bytes`);
      }
      chunks.push(chunk.subarray(0, bytesRead));
    }
  } finally {
    fs.closeSync(descriptor);
  }
  return Buffer.concat(chunks, total).toString("utf8");
}

function parseJsonFile(file, maxBytes, label) {
  try {
    return JSON.parse(readUtf8File(file, maxBytes, label));
  } catch (error) {
    if (error instanceof SyntaxError) {
      throw new Error(`${label} is not valid JSON: ${error.message}`, {
        cause: error,
      });
    }
    throw error;
  }
}

function validateHttpUrl(value, label) {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`${label} must be a non-empty HTTP(S) URL`);
  }

  let parsed;
  try {
    parsed = new URL(value);
  } catch (error) {
    throw new Error(`${label} must be a valid HTTP(S) URL`, { cause: error });
  }
  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    throw new Error(`${label} must use HTTP or HTTPS`);
  }
}

export function validateWatchers(watchers) {
  if (!Array.isArray(watchers)) {
    throw new Error("watchers config must contain an array");
  }
  if (watchers.length > MAX_WATCHERS) {
    throw new Error(`watchers config cannot contain more than ${MAX_WATCHERS} entries`);
  }

  const slugs = new Set();
  for (const [index, watcher] of watchers.entries()) {
    const label = `watchers[${index}]`;
    if (!isPlainObject(watcher)) {
      throw new Error(`${label} must be an object`);
    }
    if (watcher.enabled !== undefined && typeof watcher.enabled !== "boolean") {
      throw new Error(`${label}.enabled must be a boolean`);
    }
    if (
      typeof watcher.slug !== "string" ||
      !/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(watcher.slug)
    ) {
      throw new Error(`${label}.slug must be a safe, non-empty identifier`);
    }
    if (slugs.has(watcher.slug)) {
      throw new Error(`duplicate watcher slug: ${watcher.slug}`);
    }
    slugs.add(watcher.slug);

    if (watcher.enabled === false) continue;

    validateHttpUrl(watcher.url, `${label}.url`);
    if (watcher.fetchUrl !== undefined) {
      validateHttpUrl(watcher.fetchUrl, `${label}.fetchUrl`);
    }
    if (
      watcher.timeoutMs !== undefined &&
      (!Number.isInteger(watcher.timeoutMs) ||
        watcher.timeoutMs < 1 ||
        watcher.timeoutMs > 300000)
    ) {
      throw new Error(`${label}.timeoutMs must be an integer from 1 to 300000`);
    }
    if (
      watcher.maxResponseBytes !== undefined &&
      (!Number.isInteger(watcher.maxResponseBytes) ||
        watcher.maxResponseBytes < 1 ||
        watcher.maxResponseBytes > MAX_RESPONSE_BYTES)
    ) {
      throw new Error(
        `${label}.maxResponseBytes must be an integer from 1 to ${MAX_RESPONSE_BYTES}`,
      );
    }
    if (
      watcher.group !== undefined &&
      (!Number.isInteger(watcher.group) || watcher.group < 0)
    ) {
      throw new Error(`${label}.group must be a non-negative integer`);
    }
    if (watcher.headers !== undefined && !isPlainObject(watcher.headers)) {
      throw new Error(`${label}.headers must be an object`);
    }
    for (const [name, value] of Object.entries(watcher.headers ?? {})) {
      if (typeof value !== "string") {
        throw new Error(`${label}.headers.${name} must be a string`);
      }
    }
    for (const field of [
      "method",
      "flags",
      "label",
      "message",
      "displayTemplate",
    ]) {
      if (watcher[field] !== undefined && typeof watcher[field] !== "string") {
        throw new Error(`${label}.${field} must be a string`);
      }
    }
    if (watcher.method === "") {
      throw new Error(`${label}.method must not be empty`);
    }

    if (watcher.mode === "regex") {
      const patterns = watcher.patterns ?? [watcher.pattern];
      if (
        !Array.isArray(patterns) ||
        patterns.length === 0 ||
        patterns.some((pattern) => typeof pattern !== "string" || pattern.length === 0)
      ) {
        throw new Error(`${label} must define at least one non-empty regex pattern`);
      }
      try {
        for (const pattern of patterns) new RegExp(pattern, watcher.flags ?? "i");
      } catch (error) {
        throw new Error(`${label} contains an invalid regular expression`, {
          cause: error,
        });
      }
    } else if (
      watcher.mode !== "extractor" ||
      watcher.extractor !== "eightBitdoUltimate2cFirmware"
    ) {
      throw new Error(`Unknown watcher mode for ${watcher.slug}`);
    }
  }

  return watchers;
}

function readState(file) {
  let state;
  try {
    state = parseJsonFile(file, MAX_STATE_FILE_BYTES, "state file");
  } catch (error) {
    if (error.code === "ENOENT") return { watchers: {} };
    throw error;
  }

  if (!isPlainObject(state) || !isPlainObject(state.watchers)) {
    throw new Error("state file must contain an object with a watchers object");
  }
  for (const [slug, previous] of Object.entries(state.watchers)) {
    if (!isPlainObject(previous)) {
      throw new Error(`state for watcher ${slug} must be an object`);
    }
  }
  return state;
}

function acquireStateLock(file) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const lock = `${file}.lock`;
  const token = `${process.pid}:${randomUUID()}`;
  let descriptor;
  try {
    descriptor = fs.openSync(lock, "wx", 0o600);
    fs.writeFileSync(descriptor, `${token}\n`);
  } catch (error) {
    if (descriptor !== undefined) fs.closeSync(descriptor);
    if (error.code === "EEXIST") {
      throw new Error(`state file is already locked by another invocation: ${file}`);
    }
    throw error;
  }
  fs.closeSync(descriptor);

  let released = false;
  return () => {
    if (released) return;
    released = true;
    const currentToken = readUtf8File(lock, 256, "state lock").trim();
    if (currentToken !== token) {
      throw new Error(`state lock ownership changed unexpectedly: ${lock}`);
    }
    fs.unlinkSync(lock);
  };
}

function writeState(file, state) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.${process.pid}.${randomUUID()}.tmp`;
  try {
    fs.writeFileSync(tmp, `${JSON.stringify(state, null, 2)}\n`, {
      flag: "wx",
      mode: 0o600,
    });
    fs.renameSync(tmp, file);
  } finally {
    try {
      fs.unlinkSync(tmp);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }
}

export function stableStringify(value) {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(",")}]`;
  return `{${Object.keys(value)
    .sort()
    .map((key) => `${JSON.stringify(key)}:${stableStringify(value[key])}`)
    .join(",")}}`;
}

export function extractEightBitdoUltimate2cFirmware(body) {
  const anchor = 'id="ultimate-2c-wireless"';
  const start = body.indexOf(anchor);
  if (start === -1) {
    throw new Error("Could not find Ultimate 2C Wireless update log section");
  }

  const afterAnchor = body.slice(start + anchor.length);
  const nextUpdateLog = /<div\b[^>]*\bclass=["'][^"']*\bupdate-log\b[^"']*["'][^>]*>/i.exec(
    afterAnchor,
  );
  const section =
    nextUpdateLog === null
      ? afterAnchor
      : afterAnchor.slice(0, nextUpdateLog.index);
  const controllerMatch =
    /<!--\s*Controller firmware\s*-->[\s\S]*?<h5>\s*Firmware\s+v([^<\s]+)\s*<\/h5>/i.exec(
      section,
    );
  const adapterMatch =
    /<!--\s*Adapter firmware\s*-->[\s\S]*?<h5>\s*Firmware\s+v([^<\s]+)\s*<\/h5>/i.exec(
      section,
    );

  if (!controllerMatch) {
    throw new Error("Could not extract Ultimate 2C controller firmware version");
  }
  if (!adapterMatch) {
    throw new Error("Could not extract Ultimate 2C adapter firmware version");
  }

  return {
    controller: controllerMatch[1].trim(),
    adapter: adapterMatch[1].trim(),
  };
}

function displayValue(watcher, current, currentKey) {
  if (watcher.displayTemplate === "8bitdoFirmware") {
    return `controller v${current.controller}, adapter v${current.adapter}`;
  }
  return typeof current === "string" ? current : currentKey;
}

async function readBoundedResponse(response, maxBytes, slug) {
  const contentLength = response.headers.get("content-length");
  if (contentLength !== null) {
    const parsedLength = Number(contentLength);
    if (Number.isFinite(parsedLength) && parsedLength > maxBytes) {
      throw new Error(`${slug} response exceeds ${maxBytes} bytes`);
    }
  }
  if (response.body === null) return "";

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let bytesRead = 0;
  let text = "";
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      bytesRead += value.byteLength;
      if (bytesRead > maxBytes) {
        await reader.cancel();
        throw new Error(`${slug} response exceeds ${maxBytes} bytes`);
      }
      text += decoder.decode(value, { stream: true });
    }
    return text + decoder.decode();
  } finally {
    reader.releaseLock();
  }
}

async function fetchText(watcher, fetchImpl) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), watcher.timeoutMs ?? 30000);
  try {
    const response = await fetchImpl(watcher.fetchUrl ?? watcher.url, {
      method: watcher.method ?? "GET",
      headers: {
        "User-Agent": "change-monitor/1.0",
        Accept: "text/html,application/xhtml+xml,application/json,text/plain",
        ...(watcher.headers ?? {}),
      },
      signal: controller.signal,
    });
    if (!response.ok) {
      throw new Error(`${watcher.slug} returned HTTP ${response.status}`);
    }
    return await readBoundedResponse(
      response,
      watcher.maxResponseBytes ?? DEFAULT_MAX_RESPONSE_BYTES,
      watcher.slug,
    );
  } finally {
    clearTimeout(timeout);
  }
}

export function extractValue(watcher, body) {
  if (watcher.mode === "regex") {
    for (const pattern of watcher.patterns ?? [watcher.pattern]) {
      const match = new RegExp(pattern, watcher.flags ?? "i").exec(body);
      if (match && match[watcher.group ?? 1] !== undefined) {
        return String(match[watcher.group ?? 1]).trim();
      }
    }
    throw new Error(`Could not extract value for ${watcher.slug}`);
  }

  if (
    watcher.mode === "extractor" &&
    watcher.extractor === "eightBitdoUltimate2cFirmware"
  ) {
    return extractEightBitdoUltimate2cFirmware(body);
  }

  throw new Error(`Unknown watcher mode for ${watcher.slug}`);
}

function replaceLiteral(template, token, value) {
  return template.replaceAll(token, () => String(value));
}

async function notifyDiscord(webhookPath, content, fetchImpl) {
  const webhookUrl = readUtf8File(
    webhookPath,
    MAX_WEBHOOK_FILE_BYTES,
    "Discord webhook file",
  ).trim();
  validateHttpUrl(webhookUrl, "Discord webhook");
  const response = await fetchImpl(webhookUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username: "automations", content }),
  });
  if (!response.ok) {
    throw new Error(`Discord webhook returned HTTP ${response.status}`);
  }
}

export async function runChangeDetection({
  watchersPath,
  statePath,
  discordWebhookPath,
  fetchImpl = globalThis.fetch,
  now = () => new Date(),
  log = console.log,
  handleSignals = false,
}) {
  const watchers = validateWatchers(
    parseJsonFile(watchersPath, MAX_WATCHERS_FILE_BYTES, "watchers config"),
  );
  const releaseLock = acquireStateLock(statePath);
  const signalHandlers = new Map();
  if (handleSignals) {
    for (const [signal, exitCode] of [
      ["SIGINT", 130],
      ["SIGTERM", 143],
    ]) {
      const handler = () => {
        releaseLock();
        process.exit(exitCode);
      };
      signalHandlers.set(signal, handler);
      process.once(signal, handler);
    }
  }
  try {
    const state = readState(statePath);

    for (const watcher of watchers.filter((entry) => entry.enabled !== false)) {
      const body = await fetchText(watcher, fetchImpl);
      const current = extractValue(watcher, body);
      const currentKey =
        typeof current === "string" ? current : stableStringify(current);
      const currentDisplay = displayValue(watcher, current, currentKey);
      const previous = state.watchers[watcher.slug];
      const hasPrevious = previous !== undefined;
      const previousKey =
        previous?.currentKey ??
        (Object.hasOwn(previous ?? {}, "current")
          ? typeof previous.current === "string"
            ? previous.current
            : stableStringify(previous.current)
          : undefined);
      const previousDisplay = previous?.displayValue ?? previous?.current ?? null;
      const changed = hasPrevious && previousKey !== currentKey;

      state.watchers[watcher.slug] = {
        current,
        currentKey,
        displayValue: currentDisplay,
        checkedAt: now().toISOString(),
        url: watcher.url,
      };

      if (changed) {
        const template =
          watcher.message ??
          `${watcher.label ?? watcher.slug} changed: {{previous}} -> {{current}}\n{{url}}`;
        let content = replaceLiteral(
          template,
          "{{previous}}",
          previousDisplay ?? previousKey,
        );
        content = replaceLiteral(content, "{{current}}", currentDisplay);
        content = replaceLiteral(content, "{{url}}", watcher.url);
        await notifyDiscord(discordWebhookPath, content, fetchImpl);
        log(
          `${watcher.slug}: changed from ${previousDisplay ?? previousKey} to ${currentDisplay}`,
        );
      } else {
        log(`${watcher.slug}: unchanged at ${currentDisplay}`);
      }
    }

    writeState(statePath, state);
    return state;
  } finally {
    for (const [signal, handler] of signalHandlers) {
      process.removeListener(signal, handler);
    }
    releaseLock();
  }
}

export async function main(args = process.argv.slice(2)) {
  const [watchersPath, statePath, discordWebhookPath] = args;
  if (!watchersPath || !statePath || !discordWebhookPath) {
    throw new Error(
      "usage: change-detection <watchers.json> <state.json> <discord-webhook-file>",
    );
  }
  return runChangeDetection({
    watchersPath,
    statePath,
    discordWebhookPath,
    handleSignals: true,
  });
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href
) {
  await main();
}
