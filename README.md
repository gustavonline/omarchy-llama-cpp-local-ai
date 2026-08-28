# Local AI for Omarchy

One Omarchy bar widget for local AI: start and switch prepared **llama.cpp
server profiles**, expose their OpenAI-compatible endpoints to clients such as
Codex, and optionally enable a lightweight always-on local Copilot.

The runtime controller and Copilot are separate subsystems inside the same
plugin and the same dropdown. The Copilot consumes a configured endpoint; it
does not replace the profile controller or prevent other clients from using the
endpoint.

## Requirements

- A current Omarchy installation
- `llama-server` from a llama.cpp build suitable for the machine
- At least one local GGUF model and one tested systemd **user** service
- `python3`, `jq`, `systemctl`, and `wl-copy` (provided by a normal Omarchy setup)
- Pi (`pi`) only when the optional Copilot is enabled

The plugin does not download models, install accelerators, generate services, or
change GPU and power settings.

## Install

```bash
omarchy plugin add https://github.com/gustavonline/omarchy-llama-cpp-local-ai --enable --yes
install -Dm644 \
  ~/.config/omarchy/plugins/io.github.gustavonline.local-ai/local-ai.example.toml \
  ~/.config/omarchy/local-ai.toml
```

Prepare and test each model service using [SETUP.md](SETUP.md), then edit
`~/.config/omarchy/local-ai.toml` so every profile points to its service. Finish
with:

```bash
~/.config/omarchy/plugins/io.github.gustavonline.local-ai/local-ai-control doctor
```

## Runtime and endpoint controls

- Shows model, quantization, context, accelerator, and API endpoint discovered
  from each service's `ExecStart`.
- Starts one profile at a time and stops conflicting configured profiles.
- Stops or restarts the active profile.
- Copies its OpenAI-compatible llama.cpp URL.
- Keeps every configured model disabled at login; panel starts are session-only.
- Surfaces concrete configuration and systemd errors in the panel.

## Optional always-on Copilot

The **Always-on Copilot** section lives in the same Local AI dropdown. It is off
by default. Clicking **Set up Copilot** creates a private machine-local settings
file and opens it for editing; **Turn Copilot on** then enables a hardened
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

Copilot configuration is stored in
`~/.config/omarchy/local-ai-copilot.toml`; its editable playbook defaults to
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
For Copilot only, a named environment variable can supply the key. On a local
loopback llama.cpp service, Copilot can also resolve the matching key from the
same user's running process and writes it only to its mode-600 isolated Pi
catalog; it never enters status, UI, audit logs, or the repository.

Coding agents and other OpenAI-compatible clients remain separate consumers.
Point them at the verified endpoint after the runtime reports healthy. Enabling
Copilot does not reserve the endpoint for itself.

## Controls

- Left-click: open the profile panel
- Right-click: start the default profile or stop the active profile
- Middle-click: restart the active profile
- Panel buttons: switch profile, start, stop, restart, copy URL, or edit profiles
- Same panel: set up, enable, pause, test, restart, or disable Copilot

## Verification

```bash
./local-ai-control doctor
./local-ai-copilot --config ~/.config/omarchy/local-ai-copilot.toml doctor --online
./test.sh
```

`doctor` is read-only and exits unsuccessfully when the configuration, a declared
service, or a referenced model file is missing.

## Remove

Disable Copilot and stop the configured runtimes before removing the widget:

```bash
~/.config/omarchy/plugins/io.github.gustavonline.local-ai/local-ai-control stop
~/.config/omarchy/plugins/io.github.gustavonline.local-ai/local-ai-copilot disable
omarchy plugin remove io.github.gustavonline.local-ai --yes
```

Removal leaves GGUF files, systemd user services, and
`~/.config/omarchy/local-ai.toml`, Copilot settings, playbook, and local models
untouched.

## License

MIT.
