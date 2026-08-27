# Changelog

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
