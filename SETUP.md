# Setup contract

This plugin is a generic control surface. It does not install a backend,
download models, or guess performance settings.

## Coding-agent workflow

1. Inspect the machine, installed local-AI backends, model files, and available
   accelerators.
2. Create one user-level systemd service per useful launch profile. Profiles
   should conflict with each other when they share an endpoint or accelerator.
3. Write `~/.config/omarchy/local-ai.json` according to
   `local-ai.schema.json`.
4. Validate every required file, start the default profile, and verify the
   configured endpoint.
5. Leave only the default profile enabled.

The profile label is a short user-facing purpose such as `Fast`, `Daily`, or
`Max`. `model`, `variant`, and `context` describe what the profile actually
runs. These names are examples, not requirements.

The plugin performs readiness checks and controls the declared systemd user
services. Agent harnesses configure and consume the endpoint independently.
