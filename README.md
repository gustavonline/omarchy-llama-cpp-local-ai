# Local AI for Omarchy

A standalone Omarchy bar widget for controlling local AI runtimes without a
terminal. It does not clone, replace, or depend on Omarchy's built-in Agents
widget.

The panel discovers profiles from `~/.config/omarchy/local-ai.json`, displays
installed/ready launch profiles, starts and stops exclusive user-level systemd services,
restarts the active runtime, copies the API endpoint, and opens the configured
model directory.

A profile is not necessarily a distinct model. For example, Fast, Daily, and
Max may launch three quantizations of the same base model with different
context, draft-model, and backend settings. The optional `model`, `variant`,
and `context` fields keep that distinction clear in the panel.

Ollama-owned models can be discovered from Ollama's registry by a future
backend adapter. Raw GGUF directories are intentionally not treated as
directly runnable: a filename alone does not describe draft-model pairing,
context size, GPU offload, cache type, or other required launch arguments.

Backends and harnesses are intentionally separate. Profiles may represent
llama.cpp, Ollama, vLLM, or another local server; Pi, Codex, Claude Code, and
other clients configure the endpoint independently.

See `local-ai.example.json` for the configuration shape.
