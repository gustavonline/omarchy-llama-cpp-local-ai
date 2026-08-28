# Always-on Assistant acceptance tests

These tests cover the current metadata-only release. They do not require screen
capture, computer use, AIOS access, or an autonomous agent harness.

## Before testing

Open **Local AI → Assistant settings** and confirm that a small local model is
selected. Choose **Preferred harness**, or keep **Choose each time** if the
suggestion card should always ask. Keep any shared runtime used by Codex or
Local Transcript running.
Use this command in a terminal to watch service errors without exposing prompt
content:

```bash
journalctl --user -u omarchy-local-ai-copilot.service -f
```

## 1. Toggle and persistence

1. Turn **Always-on Assistant** on.
2. Reopen the panel and confirm the state becomes **Watching**.
3. Log out and back in when convenient, then confirm it starts automatically.
4. Turn it off and confirm the service no longer runs.

Expected: the toggle mirrors the systemd user service; turning it off also
clears any visible suggestion. This test must not start or stop the separate
Local AI runtime profiles.

## 2. Quiet normal work

Enable the assistant and work normally for 10–15 minutes in non-sensitive apps.
Start with **Balanced** frequency.

Expected: the panel usually stays at **Watching**. The assistant should prefer
silence over vague advice and must respect its hourly and per-context limits.
Record any repetitive or generic suggestion as a relevance failure.

## 3. Real suggestion and quick actions

Keep the assistant on during ordinary non-sensitive work. When a real
suggestion appears, confirm that it stays at the bottom right without taking
keyboard focus. Try the fixed actions across separate suggestions:

- **Dismiss** closes it without another action.
- **Copy draft** places the bounded draft on the clipboard.
- **Remember** saves a small app-scoped hint to the local playbook.
- **Continue in…** lists detected harnesses and highlights the preferred one.

Expected: the card disappears after the chosen action or its short expiry. It
is valid for no card to appear during routine work: silence is the intended
result when the model has no high-confidence help. The `test-suggestion` CLI
command is an internal regression fixture and is not part of normal testing.

## 4. Native privacy picker

1. Open **Assistant settings → Blocked apps**.
2. Select a harmless app to use as the test target and save.
3. Focus that app and leave it active for at least 20 seconds.

Expected: that window context produces no suggestion. Password managers and
sensitive title patterns remain blocked even if the extra app list is empty.
Remove the harmless test app afterwards if you want it observed normally.

## 5. Window-title boundary

Turn **Use window titles** off, save, and use several apps.

Expected: the assistant may receive the bounded application class and workspace,
but never the active-window title. Re-enable the setting only if title metadata
is useful enough for your workflow.

## 6. Frequency comparison

Use **Quiet**, **Balanced**, and **More proactive** for comparable 30-minute work
sessions.

Record for each session:

- number of suggestions;
- useful, irrelevant, or unsafe;
- approximate time from context change to suggestion;
- whether the suggestion interrupted focus.

The default should not change based on one anecdote; compare the same workflows
and model where possible.

## 7. Explicit heavy-harness handoff

On a real suggestion with a handoff goal, click **Continue in…**, select the
preferred harness, and verify that a visible terminal opens with a bounded
prefilled task. Repeat later with a non-default installed harness to verify the
per-suggestion chooser.

Expected: nothing is delegated before the click. The lightweight assistant does
not inherit the heavy harness's tools or permissions, and it does not mutate the
workspace itself.

## Current limits to report, not debug

- It sees filtered app/window metadata, not screen pixels or document contents.
- There is no conversational reply field, push-to-talk, or ongoing chat yet.
- It cannot operate the desktop or approve actions.
- AIOS linking and reviewed context/PR proposals are not implemented yet.
- Suggestion quality is constrained by the selected small local model.

For a useful bug report, include the app class, sanitized window-title shape,
selected frequency/model, expected behavior, observed behavior, and approximate
latency. Never paste passwords, private document text, API keys, or raw sensitive
titles.
