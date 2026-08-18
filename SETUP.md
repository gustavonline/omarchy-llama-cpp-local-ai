# Setup contract

This plugin is a generic control surface. It does not install a backend,
download models, or guess performance settings.

## Coding-agent workflow

1. Inspect the machine, installed local-AI backends, model files, and available
   accelerators.
2. Create one user-level systemd service per useful launch profile. Profiles
   should conflict with each other when they share an endpoint or accelerator.
3. Copy `local-ai.example.toml` to `~/.config/omarchy/local-ai.toml` and fill
   in the short, commented profile list.
4. Validate every required file, start the default profile, and verify the
   configured endpoint.
5. Leave only the default profile enabled.

Each profile has one freely chosen `name`; there is no separate ID or fixed
Fast/Daily/Max meaning. Profiles may run variants of one model or entirely
different models. `service` connects the display entry to its systemd user
service; the remaining technical launch arguments stay in that service.

The plugin performs readiness checks and controls the declared systemd user
services. Agent harnesses configure and consume the endpoint independently.
