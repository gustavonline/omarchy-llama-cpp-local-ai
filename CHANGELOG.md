# Changelog

## 0.7.0 — 2026-08-28

- Simplify the main panel around one always-on Copilot toggle and one settings
  action, removing pause, restart, playbook, and test controls from the normal UI
- Put Copilot first and keep runtime profiles, endpoint actions, and model
  controls together in the lower Local AI section
- Add a Local Transcript-inspired settings page with back navigation, native
  model/frequency dropdowns, window-title privacy toggle, and save feedback
- Discover compatible models from active local Ollama and llama.cpp endpoints
  and identify the smallest available model for the lightweight Copilot
- Preserve the advanced TOML editor for uncommon endpoint, startup, delegation,
  privacy, and rate-limit configuration

## 0.6.0 — 2026-08-28

- Add the opt-in always-on local Copilot inside the existing Local AI dropdown
  instead of creating a second Omarchy plugin or menubar icon
- Add an event-driven, privacy-filtered Hyprland observer backed by a minimal
  isolated Pi session and a configurable local OpenAI-compatible endpoint
- Add non-focus-stealing bottom-right suggestions with dismiss, copy, remember,
  and explicit optional heavy-harness delegation actions
- Add private machine-local Copilot settings, editable playbook memory,
  metadata-only audit logs, confidence/cooldown limits, and a hardened systemd
  user service
- Preserve the existing runtime-profile controller and endpoint workflow as an
  independent subsystem inside the same plugin

## 0.5.1 — 2026-08-27

- Make standalone validation portable to clean GitHub Actions runners

## 0.5.0 — 2026-08-27

- Use the concise, machine-independent `Local AI` title while keeping the
  llama.cpp runtime scope explicit in descriptions and documentation
- Add complete public installation, prerequisite, security, and removal guidance
- Surface concrete runtime and systemd errors in the panel
- Clear successful action feedback automatically after a short delay while keeping errors visible
- Validate configured systemd user service names and harden systemctl argument handling
- Make `doctor` fail clearly when its configuration file is missing
- Add GitHub Actions validation and a release checklist

## 0.4.0

- Rename the user-facing plugin to llama.cpp Local AI while retaining its
  stable plugin ID and configuration paths.

## 0.3.0

- Discover model, quantization, context, accelerator, and endpoint directly
  from each configured llama.cpp service.
- Keep the editable configuration to profile names and service names.
- Keep all runtimes disabled at login and start them only on demand.
- Add a read-only doctor command and regression coverage for profile startup.
- Fix profile startup failing before systemd was called.
- Improve bar-icon contrast while retaining the active-runtime indicator.

## 0.2.0

- Replace the verbose JSON configuration with a short, commented TOML file.
- Use one freely chosen profile name instead of separate IDs and labels.
- Allow every profile to describe a different model, variant, and context.

## 0.1.0

- Add a standalone Local AI bar icon and panel.
- Add configurable runtime profiles and readiness checks.
- Add start, stop, restart, endpoint-copy, and model-folder shortcuts.
- Distinguish base models, variants, and launch profiles in the panel.
- Add native Open config support and an agent-friendly setup contract.
