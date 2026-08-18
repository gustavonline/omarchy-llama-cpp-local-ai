# Local AI for Omarchy

A standalone Omarchy bar widget for controlling local AI runtimes without a
terminal. It does not clone, replace, or depend on Omarchy's built-in Agents
widget.

The panel discovers profiles from `~/.config/omarchy/local-ai.json`, displays
installed/ready models, starts and stops exclusive user-level systemd services,
restarts the active runtime, copies the API endpoint, and opens the configured
model directory.

Backends and harnesses are intentionally separate. Profiles may represent
llama.cpp, Ollama, vLLM, or another local server; Pi, Codex, Claude Code, and
other clients configure the endpoint independently.

See `local-ai.example.json` for the configuration shape.
