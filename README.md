# Local AI for Omarchy

One Omarchy bar widget for local AI: start and switch prepared **llama.cpp
model runtimes**, expose their OpenAI-compatible endpoints to clients such as
Codex, and optionally enable a lightweight always-on local assistant.

The runtime controller and assistant are separate subsystems inside the same
plugin and the same dropdown. The assistant consumes a configured endpoint; it
does not replace the profile controller or prevent other clients from using the
endpoint.

## Requirements

- A current Omarchy installation
- `llama-server` from a llama.cpp build suitable for the machine
- At least one local GGUF model and one tested systemd **user** service
- `python3`, `jq`, `systemctl`, and `wl-copy` (provided by a normal Omarchy setup)
- Pi (`pi`) only when the optional assistant is enabled

The plugin does not download models, install accelerators, generate services, or
change GPU and power settings.

## Install

```bash
omarchy plugin add https://github.com/gustavonline/omarchy-llama-cpp-local-ai --enable --yes
install -Dm644 \
  ~/.config/omarchy/plugins/gustav.local-ai/local-ai.example.toml \
  ~/.config/omarchy/local-ai.toml
```

Prepare and test each model service using [SETUP.md](SETUP.md), then edit
`~/.config/omarchy/local-ai.toml` so every profile points to its service. Finish
with:

```bash
~/.config/omarchy/plugins/gustav.local-ai/local-ai-control doctor
```

## Runtime and endpoint controls

- Shows model, quantization, context, accelerator, and API endpoint discovered
  from each service's `ExecStart`.
- Starts one actual model runtime at a time and stops conflicting configured runtimes.
- Keeps runtime display names independent from downloaded filenames and generic
  engine service names; quantization remains visible only as technical detail.
- Stops or restarts the active profile.
- Copies its OpenAI-compatible llama.cpp URL.
- Keeps every configured model disabled at login; panel starts are session-only.
- Reads arbitrary runtime display names from the advanced profile config; model,
  quantization, context, and systemd service remain separate discovered details.
- Surfaces concrete configuration and systemd errors in the panel.

## Optional always-on assistant

The **Always-on Assistant** section appears first in the same Local AI dropdown.
It is off by default and uses one persistent toggle. The adjacent settings page
discovers compatible models from active local Ollama and llama.cpp endpoints,
lets the user choose suggestion frequency, a preferred installed harness,
window-title sharing, and extra blocked apps using native controls, and saves a
private machine-local configuration. Turning the toggle on enables a hardened
systemd user service that starts after graphical login.

Frequency is a complete behavior preset rather than only a confidence label.
**Proactive** uses a two-second debounce, checks every eight seconds as a fallback,
allows revisiting a context after 120 seconds, and permits up to eight useful
suggestions per hour. Frequent checks do not lower the relevance boundary:
generic browser, entertainment, and self-window contexts are rejected before
inference, while output still needs a concrete action to reach the UI.

The first version is deliberately light and quiet:

- Watches filtered Hyprland window changes, with debounce and per-context
  cooldowns rather than continuous screen capture.
- Sends only bounded window metadata to an isolated, tool-less Pi session using
  the selected local OpenAI-compatible endpoint.
- Shows validated suggestions in a non-focus-stealing card at the bottom right;
  supports dismiss, a small contextual copy control, and editable playbook memory.
  Dismiss teaches a separate negative preference scoped to the generated
  suggestion plus app and normalized page tags—such as Zen + YouTube—not the
  entire app. The Assistant maintains each learned point in the readable private
  file `~/.local/state/omarchy/local-ai-assistant/memory.md`, available through
  **View learned memory** in Settings. If the same suggestion pattern is rejected
  in two distinct contexts, it becomes global. Examples expire after 30 days and
  can be reset in Settings.
- Uses the existing Local AI bar icon for explicit voice status. Hold `SUPER + A`
  to speak: the icon becomes a blue live waveform; release to transcribe and
  submit, shown as a light loading pulse. The local Pi response then streams into
  the same bottom-right surface used by suggestions. It remains tool-less and
  can hand larger work to the preferred harness only after a click.
- Discovers installed Codex, Claude Code, Gemini CLI, Pi Worker, and Pi
  commands. Each card has one **Continue in [harness]** button that follows the
  preferred harness selected in Settings. A click creates a private, portable
  handoff session, copies only its `SESSION.md` path, and opens the harness; the
  light model cannot launch it by itself.
- Never takes screenshots, runs shell tools, or mutates the desktop in this
  release.

Assistant configuration is stored in
the `[assistant.*]` tables of `~/.config/omarchy/local-ai.toml`. **Open full Local AI config** exposes the
full TOML for unusual startup/delegation/privacy settings; its editable playbook defaults to
`~/.config/omarchy/local-ai-assistant-playbook.json`. See the annotated
[`local-ai.example.toml`](local-ai.example.toml).

The learned `memory.md` is maintained by Dismiss and is intentionally separate
from the explicit playbook: memory suppresses unwanted recurring suggestions,
while playbook rules positively tell the Assistant what may be useful.

## Profiles

The user configuration is intentionally only an index of model-agnostic runtime
slots:

```toml
default = "Qwen"

[[profiles]]
name = "Qwen"
service = "omarchy-local-ai-runtime-1.service"

[[profiles]]
name = "Gemma"
service = "omarchy-local-ai-runtime-2.service"

[[profiles]]
name = "Vision"
service = "omarchy-local-ai-runtime-3.service"
```

Profile names are arbitrary and edited in the advanced runtime config. Each profile represents one
actual model; Q4/Q8/BF16 is discovered technical metadata rather than a profile
identity. Optional `summary` and `endpoint` fields override display text or the
copied URL for unusual launch commands, but never change how a runtime starts.

Do not put model paths or llama.cpp flags in the TOML file. The service remains
the source of truth, and the plugin reads `--model`, `--spec-draft-model`,
`--ctx-size`, `--device`, `--host`, and `--port` from `ExecStart`. **Open
advanced runtime config** opens both this index and the selected slot's service
file so per-model context/cache/GPU settings are reachable without exposing them
in the compact dropdown.

## Security and clients

Bind local inference services to `127.0.0.1` unless network access is intentional.
If a service uses `--api-key`, configure that key in each external client
separately. The panel copies only the endpoint and never displays credentials.
For the assistant only, a named environment variable can supply the key. On a local
loopback llama.cpp service, the assistant can also resolve the matching key from the
same user's running process and writes it only to its mode-600 isolated Pi
catalog; it never enters status, UI, audit logs, or the repository.

Coding agents and other OpenAI-compatible clients remain separate consumers.
Point them at the verified endpoint after the runtime reports healthy. Enabling
the assistant does not reserve the endpoint for itself.

### How proactive suggestions are produced

The observer reads the active Hyprland application class, workspace, and—only
when enabled—the filtered window title. Protected apps and sensitive title
patterns are discarded before inference. After debounce and cooldown checks,
an isolated Pi process sends that bounded metadata plus user-approved playbook
hints to the selected local model. Pi starts offline with tools, extensions,
skills, context files, and session memory disabled. One checked-in
[`prompts/assistant-system.md`](prompts/assistant-system.md) defines the shared
identity, privacy boundary, and the explicit `proactive` and `direct` interaction
modes. Proactive mode asks for either silence or one strict JSON suggestion;
direct mode returns concise plain text. The plugin independently validates context,
actionability, confidence, and length, enforces hourly and per-context limits,
and shows the result for a short time.
Unfocused suggestions count down from 30 seconds; hover or keyboard focus pauses
the timer and leaving the card starts a fresh 30-second window.

The card has only two persistent actions: **Dismiss** and
**Continue in [preferred harness]**. A small copy control appears after the
rendered response at its lower right while the card is hovered or focused and does not close the card. The
same interaction expands the complete model response inside the fixed-size,
scrollable card; arrow and Page Up/Page Down keys work when it has keyboard
focus. Primary actions remain anchored at the card bottom while copy sits at
the response's lower right. `Continue` creates a new harness-neutral session
under `~/.local/state/agent-handoffs/local-ai/`, copies the absolute `SESSION.md`
path, and opens the preferred installed harness. The session also contains
machine-readable `session.json`; nothing is automatically pasted or submitted.

`memory.md` is not a second system prompt. It is a readable view of learned
dismissals; the machine-readable JSON remains the source of truth, and only
relevant, bounded examples are added to proactive requests. An `AGENTS.md` is
deliberately not loaded: the isolated Pi invocation disables harness context files
so repository instructions cannot silently change the always-on assistant.

### Hold to ask

On this machine, holding `SUPER + A` starts Voxtype and turns the existing Local
AI bar icon into a small blue waveform. Release the keys to stop recording; the
icon becomes a light loading pulse while Voxtype writes the transcript to a
private per-turn file. Local AI reads that file and submits it directly without
typing text or Enter into any focused app. The temporary transcript is deleted
after reading. Repeated key-down events while the chord remains held are ignored,
and the interaction rearms for the next complete hold/release turn.

The binding stays in the user's Omarchy bindings rather than being claimed
globally by the plugin, so installation can verify that the chord is free. Voice
capture never opens or focuses another window. When the response begins, the
standard unfocused bottom-right surface appears and streams the result. The same
surface provides the explicit text field when Local AI is summoned in text mode.

The direct response is streamed from the selected local model. It has no tools,
desktop control, web access, or hidden agent permissions. **Continue in
[preferred harness]** turns the request and local response into a bounded task
only when the user explicitly clicks it.

When Pi Worker v0.6 or newer is the preferred harness, Local AI supplies the
captured working directory, a stable `local-ai-*` job ID, and explicit text
output. Pi Worker keeps its read-only `inspect` profile and progressively loaded
machine/project skills unless advanced config deliberately overrides them.

## Controls

- Left-click: open the profile panel
- Right-click: start the default profile or stop the active profile
- Middle-click: restart the active profile
- Panel buttons: switch runtime, start, stop, restart, copy URL, or open the
  selected model's advanced engine configuration. Runtime display names live
  in that advanced configuration instead of a separate panel action.
- Same panel: toggle the assistant and open its dedicated settings page
- User shortcut: hold `SUPER + A` to speak, then release to submit (configured
  on this machine after a conflict check)
- Manual acceptance scenarios: [`docs/ASSISTANT-TESTING.md`](docs/ASSISTANT-TESTING.md)

## Verification

```bash
./local-ai-control doctor
./local-ai-assistant --config ~/.config/omarchy/local-ai-assistant.toml doctor --online
./test.sh
```

`doctor` is read-only and exits unsuccessfully when the configuration, a declared
service, or a referenced model file is missing.

## Remove

Disable the assistant and stop the configured runtimes before removing the widget:

```bash
~/.config/omarchy/plugins/gustav.local-ai/local-ai-control stop
~/.config/omarchy/plugins/gustav.local-ai/local-ai-assistant disable
omarchy plugin remove io.github.gustavonline.local-ai --yes
```

Removal leaves GGUF files, systemd user services, and
`~/.config/omarchy/local-ai.toml`, assistant settings, playbook, and local models
untouched.

## License

MIT.
