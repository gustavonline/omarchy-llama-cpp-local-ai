# Local AI for Omarchy

One Omarchy bar widget for local AI: start and switch prepared **llama.cpp
server profiles**, expose their OpenAI-compatible endpoints to clients such as
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
- Starts one profile at a time and stops conflicting configured profiles.
- Stops or restarts the active profile.
- Copies its OpenAI-compatible llama.cpp URL.
- Keeps every configured model disabled at login; panel starts are session-only.
- Surfaces concrete configuration and systemd errors in the panel.

## Optional always-on assistant

The **Always-on Assistant** section appears first in the same Local AI dropdown.
It is off by default and uses one persistent toggle. The adjacent settings page
discovers compatible models from active local Ollama and llama.cpp endpoints,
lets the user choose suggestion frequency, window-title sharing, and extra
blocked apps using a native installed-app picker, and saves a private
machine-local configuration. Turning the toggle on enables a hardened
systemd user service that starts after graphical login.

The first version is deliberately light and quiet:

- Watches filtered Hyprland window changes, with debounce and per-context
  cooldowns rather than continuous screen capture.
- Sends only bounded window metadata to an isolated, tool-less Pi session using
  the selected local OpenAI-compatible endpoint.
- Shows high-confidence suggestions in a non-focus-stealing card at the bottom
  right; supports dismiss, copy, and explicit editable playbook memory.
- Can offer an explicit **Delegate** action when `pi-worker` or another fixed
  heavy-harness command is configured. The light model cannot launch it by
  itself.
- Never takes screenshots, runs shell tools, or mutates the desktop in this
  release.

Assistant configuration is stored in
`~/.config/omarchy/local-ai-copilot.toml`. **Open advanced config** exposes the
full TOML for unusual startup/delegation/privacy settings; its editable playbook defaults to
`~/.config/omarchy/local-ai-copilot-playbook.json`. See the annotated
[`local-ai-copilot.example.toml`](local-ai-copilot.example.toml).

## Profiles

The user configuration is intentionally only an index of prepared services:

```toml
default = "Balanced"

[[profiles]]
name = "Quick"
service = "local-ai-quick.service"

[[profiles]]
name = "Balanced"
service = "local-ai-balanced.service"

[[profiles]]
name = "Gemma"
service = "gemma.service"
```

Profile names are arbitrary. Profiles may be quantizations of one model or
completely different models. Optional `summary` and `endpoint` fields override
display text or the copied URL for unusual launch commands, but never change how
a runtime starts.

Do not put model paths or llama.cpp flags in the TOML file. The service remains
the source of truth, and the plugin reads `--model`, `--spec-draft-model`,
`--ctx-size`, `--device`, `--host`, and `--port` from `ExecStart`.

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
The assistant does not reserve the endpoint for itself.

## Controls

- Left-click: open the profile panel
- Right-click: start the default profile or stop the active profile
- Middle-click: restart the active profile
- Panel buttons: switch profile, start, stop, restart, copy URL, or edit profiles
- Same panel: toggle the assistant and open its dedicated settings page
- Manual acceptance scenarios: [`docs/ASSISTANT-TESTING.md`](docs/ASSISTANT-TESTING.md)

## Verification

```bash
./local-ai-control doctor
./local-ai-copilot --config ~/.config/omarchy/local-ai-copilot.toml doctor --online
./test.sh
```

`doctor` is read-only and exits unsuccessfully when the configuration, a declared
service, or a referenced model file is missing.

## Remove

Disable the assistant and stop the configured runtimes before removing the widget:

```bash
~/.config/omarchy/plugins/gustav.local-ai/local-ai-control stop
~/.config/omarchy/plugins/gustav.local-ai/local-ai-copilot disable
omarchy plugin remove io.github.gustavonline.local-ai --yes
```

Removal leaves GGUF files, systemd user services, and
`~/.config/omarchy/local-ai.toml`, assistant settings, playbook, and local models
untouched.

## License

MIT.
