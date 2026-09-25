# Always-on Assistant acceptance tests

These tests cover the current metadata-only release. They do not require screen
capture, computer use, AIOS access, or an autonomous agent harness.

## Before testing

Open **Local AI → Assistant settings** and confirm that a small local model and
one **Preferred harness** are selected. Keep any shared runtime used by Codex
or Local Transcript running.
Use this command in a terminal to watch service errors without exposing prompt
content:

```bash
journalctl --user -u omarchy-local-ai-assistant.service -f
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
Dismiss a noisy card, return to the same kind of app/page context, and confirm a
materially similar suggestion does not immediately reappear. A different
context should not be penalized after only one dismissal. Rejecting the same
pattern in two distinct contexts makes it global until the 30-day memory expires
or **Reset learned dismissals** is used in Settings.

After dismissing, open **Assistant settings → View learned memory**. Expected:
`memory.md` contains a new **Avoid suggesting** point with its dismissal count,
learning level, expiry, app, and bounded page tags. A second matching dismissal
updates that point rather than creating opaque duplicate state.

## 3. Real suggestion and quick actions

Keep the assistant on during ordinary non-sensitive work. When a real
suggestion appears, confirm that it stays at the bottom right without taking
keyboard focus. Try the fixed actions across separate suggestions:

- **Dismiss** closes it without another action.
- Hover or focus the card and use the small copy icon below the response at its lower right; copying
  must leave the card open.
- Confirm long output expands on hover/focus and can be read by scrolling or by
  using Up/Down and Page Up/Page Down while the window is focused.
- **Continue in [harness]** opens the preferred harness selected in Settings.

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

## 5. Hold to ask

1. Hold the configured shortcut (`SUPER + A` on this machine) and start
   speaking immediately.
2. Confirm the existing Local AI menu-bar icon becomes a small blue live
   waveform. No voice window or second bar icon should appear.
3. Release the keys. Confirm the icon changes to a light loading pulse, then
   submits by itself without another key press.
4. Confirm keyboard focus never leaves the window you were using and no
   transcript or Enter key appears in that app. The unfocused bottom-right
   response should then appear progressively rather than all at once.
5. As soon as the first turn has completed, hold and release `SUPER + A` again.
   Confirm exactly one new recording starts and exactly one request is sent.
6. Try one very short tap and one longer sentence. Neither should leave the
   microphone stuck or prevent the next turn.
7. Use **Dismiss** or close the bottom-right response and confirm it stays closed.

Expected: explicit voice is user-initiated and never takes focus. Voxtype writes
to a private temporary file rather than the active app. Key-repeat events during
one hold are ignored, release submits once, and the state returns to idle for the
next turn. The direct response has no tools. Copy or the preferred-harness
Continue action appears only after a response.

## 6. Window-title boundary

Turn **Use window titles** off, save, and use several apps.

Expected: the assistant may receive the bounded application class and workspace,
but never the active-window title. Re-enable the setting only if title metadata
is useful enough for your workflow.

## 7. Frequency comparison

Use **Quiet**, **Balanced**, and **Proactive** for comparable 30-minute work
sessions.

Record for each session:

- number of suggestions;
- useful, irrelevant, or unsafe;
- approximate time from context change to suggestion;
- whether the suggestion interrupted focus.

The default should not change based on one anecdote; compare the same workflows
and model where possible.

## 8. Explicit heavy-harness handoff

On a real suggestion with a handoff goal, click **Continue in [harness]** and
verify that the preferred harness opens without a prefilled task. Paste once and
confirm the clipboard contains only an absolute `SESSION.md` path. Inspect its
directory: it should also contain `session.json`, and both files should describe
the observation, local response, working directory, and any direct request.
Change **Preferred harness** in Settings and repeat to verify that the card
follows the saved choice and creates a distinct session.

Expected: nothing is delegated before the click. The lightweight assistant does
not inherit the heavy harness's tools or permissions, and it does not mutate the
workspace itself. No prompt is automatically pasted or submitted.

## Optional model comparison

Before changing the default light model, compare candidates against the same
small decision set with thinking disabled:

```bash
python tests/benchmark-assistant-model.py \
  --endpoint http://127.0.0.1:11434/v1 \
  --model MODEL_ID \
  --api-key ollama \
  --repeat 5
```

The fixture checks that passive video and generic browser contexts stay silent
while a concrete failing-test context with a matching user-approved hint yields
one valid suggestion. Treat it as a regression signal, not a general model
quality benchmark; latency and all decisions should be reviewed together.

## Current limits to report, not debug

- It sees filtered app/window metadata, not screen pixels or document contents.
- Summon is one direct local turn, not a persistent conversational session.
- Dictation uses the installed Voxtype engine but owns the hold/release flow,
  menu-bar waveform/loading state, private-file handoff, temporary OSD
  suppression, and automatic submission.
- It cannot operate the desktop or approve actions.
- AIOS linking and reviewed context/PR proposals are not implemented yet.
- Suggestion quality is constrained by the selected small local model.

For a useful bug report, include the app class, sanitized window-title shape,
selected frequency/model, expected behavior, observed behavior, and approximate
latency. Never paste passwords, private document text, API keys, or raw sensitive
titles.
