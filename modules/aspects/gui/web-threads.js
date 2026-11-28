(async () => {
  const url = new URL(location.href);
  const gemini =
    url.origin === "https://gemini.google.com" && url.pathname === "/app";
  if (
    window.top !== window ||
    (!gemini && !(url.origin === "https://chatgpt.com" && url.pathname === "/"))
  ) {
    return;
  }

  const task = gemini && url.searchParams.has("task");
  const prompt = url.searchParams.get(task ? "task" : "q");
  if (prompt === null) return;

  // Consume the launch parameters before waiting for SPA hydration.
  url.searchParams.delete("q");
  if (gemini) url.searchParams.delete("task");
  history.replaceState(history.state, "", url);
  if (!prompt.trim()) return;

  // Keep site-specific selector fallbacks here. Task mode must report that
  // it is active before the script can send the prompt.
  const editorSelector = gemini
    ? 'rich-textarea [contenteditable="true"], [role="textbox"][contenteditable="true"]'
    : '#prompt-textarea, textarea[name="prompt-textarea"]';
  const sendSelector = gemini
    ? 'button[aria-label="Send message" i], button[aria-label="Send" i], button.send-button'
    : 'button[data-testid="send-button"], button#composer-submit-button[aria-label="Send prompt" i], button[aria-label="Send prompt" i]';
  const taskSelector =
    'button[aria-label="Task" i], button[aria-label="Tasks" i], [role="switch"][aria-label="Task" i]';
  const activeTaskSelector =
    ":is(" +
    taskSelector +
    ')[aria-pressed="true"], :is(' +
    taskSelector +
    ')[aria-checked="true"], button[aria-label="Remove Task" i]';

  const visible = (selector) =>
    Array.from(document.querySelectorAll(selector)).find(
      (element) => element.getClientRects().length,
    );
  const enabled = (element) =>
    element && !element.matches(':disabled, [aria-disabled="true"]');
  const deadline = performance.now() + 15000;
  async function waitFor(find, description) {
    while (performance.now() < deadline) {
      if (location.href !== url.href) throw new Error("The page navigated");
      const match = find();
      if (match) return match;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    throw new Error("Timed out waiting for " + description);
  }

  const readEditor = (editor) => editor.value ?? editor.innerText;
  try {
    if (task && !visible(activeTaskSelector)) {
      const toggle = await waitFor(() => {
        const candidate = visible(taskSelector);
        return enabled(candidate) && candidate;
      }, "the Gemini Task toggle");
      if (!visible(activeTaskSelector)) toggle.click();
      await waitFor(
        () => visible(activeTaskSelector),
        "active Gemini Task mode",
      );
    }

    const editor = await waitFor(
      () => visible(editorSelector),
      "the prompt editor",
    );
    const existing = readEditor(editor);
    if (existing.trim() && existing !== prompt) return;

    if (existing !== prompt) {
      editor.focus();
      if (editor instanceof HTMLTextAreaElement) {
        Object.getOwnPropertyDescriptor(
          HTMLTextAreaElement.prototype,
          "value",
        ).set.call(editor, prompt);
        editor.dispatchEvent(new Event("input", { bubbles: true }));
      } else {
        // Use the browser editing operation so rich-text editors receive input.
        document.execCommand("selectAll", false);
        document.execCommand("insertText", false, prompt);
      }
    }

    const send = await waitFor(() => {
      const candidate = visible(sendSelector);
      return enabled(candidate) && candidate;
    }, "an enabled Send button");

    if (
      editor.isConnected &&
      readEditor(editor).trim() === prompt.trim() &&
      (!task || visible(activeTaskSelector))
    ) {
      send.click();
    }
  } catch (error) {
    console.warn("Web thread shortcut:", error.message);
  }
})();
