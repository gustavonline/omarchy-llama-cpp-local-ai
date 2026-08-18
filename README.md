# Local AI for Omarchy

An Omarchy bar widget for starting and switching **prepared llama.cpp server
profiles** without opening a terminal.

This is deliberately a runtime switcher, not a model manager. A downloaded
GGUF file is not automatically runnable: llama.cpp still needs choices such as
context size, GPU offload, cache types, endpoint, and possibly a matching draft
model. Those choices live in normal systemd user services, where they remain
testable and visible in the journal. The plugin only provides a clean control
surface for those services.

## What the panel does

- Shows the model, quantization, context, accelerator, and API endpoint detected
  from each service's `ExecStart`.
- Starts one profile at a time and stops conflicting profiles.
- Stops or restarts the active profile.
- Copies its OpenAI-compatible llama.cpp URL.
- Keeps every model disabled at login; starting from the panel is session-only.

The plugin does **not** download models, generate performance settings, alter
llama.cpp, configure coding agents, or maintain its own model database.

## Profiles

The user configuration is intentionally only an index of prepared services:

```toml
default = "Q8"

[[profiles]]
name = "Q4"
service = "qwen-fast.service"

[[profiles]]
name = "Q8"
service = "qwen-balanced.service"

[[profiles]]
name = "Gemma"
service = "gemma.service"
```

It lives at `~/.config/omarchy/local-ai.toml`. Profile names are arbitrary;
three profiles may be three quantizations of one model or three completely
different models.

To add a downloaded Gemma GGUF, create and test `gemma.service`, then add the
two-line `Gemma` entry above. This one-time machine-specific setup is a good
task for a coding agent. The agent should follow [SETUP.md](SETUP.md), while the
user only needs the finished profile buttons.

Do not put model paths or llama.cpp launch flags in the TOML file. The plugin
discovers them from each service. Optional `summary` and `endpoint` fields may
override display text or the copied URL for unusual commands, but never affect
how a model launches.

## Verification

```bash
./local-ai-control doctor
./test.sh
```

`doctor` is read-only. It reports whether every declared service and referenced
model file is ready.

## Why not Ollama?

Ollama and plugins such as Colophon are better when the priority is a general
model library with simple download-and-run behavior. This plugin exists for
llama.cpp profiles that need explicit hardware tuning, raw GGUF files, or
special launch arrangements such as a separate speculative draft model. It
does not try to recreate Ollama.
