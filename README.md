# Local AI for Omarchy

An Omarchy bar widget for starting and switching prepared **llama.cpp server
profiles** without opening a terminal.

The plugin is deliberately a runtime controller, not a model manager. Models,
hardware tuning, context, cache types, authentication, and speculative decoding
stay in ordinary systemd user services. The repository contains no model paths,
API keys, or machine-specific launch settings.

## Requirements

- A current Omarchy installation
- `llama-server` from a llama.cpp build suitable for the machine
- At least one local GGUF model and one tested systemd **user** service
- `python3`, `jq`, `systemctl`, and `wl-copy` (provided by a normal Omarchy setup)

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

## What the panel does

- Shows model, quantization, context, accelerator, and API endpoint discovered
  from each service's `ExecStart`.
- Starts one profile at a time and stops conflicting configured profiles.
- Stops or restarts the active profile.
- Copies its OpenAI-compatible llama.cpp URL.
- Keeps every configured model disabled at login; panel starts are session-only.
- Surfaces concrete configuration and systemd errors in the panel.

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
If a service uses `--api-key`, configure that key in each client separately. The
panel copies only the endpoint and never reads, displays, or stores credentials.

Coding agents and other OpenAI-compatible clients are separate from this plugin.
Point them at the verified endpoint after the runtime reports healthy.

## Controls

- Left-click: open the profile panel
- Right-click: start the default profile or stop the active profile
- Middle-click: restart the active profile
- Panel buttons: switch profile, start, stop, restart, copy URL, or edit profiles

## Verification

```bash
./local-ai-control doctor
./test.sh
```

`doctor` is read-only and exits unsuccessfully when the configuration, a declared
service, or a referenced model file is missing.

## Remove

Stop the configured runtimes before removing the widget:

```bash
~/.config/omarchy/plugins/io.github.gustavonline.local-ai/local-ai-control stop
omarchy plugin remove io.github.gustavonline.local-ai --yes
```

Removal leaves GGUF files, systemd user services, and
`~/.config/omarchy/local-ai.toml` untouched.

## License

MIT.
