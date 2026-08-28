# Release checklist

1. Update `manifest.json` and `CHANGELOG.md` to the same semantic version.
2. Run `./test.sh` on a current Omarchy installation.
3. Install from a fresh clone and verify missing-config, ready-profile, start,
   switch, restart, stop, endpoint copy, Copilot setup/enable/pause/disable,
   suggestion-card actions, and error-display behavior.
4. Confirm the repository contains no models, API keys, local TOML files,
   machine-specific services, Copilot settings/playbooks, or hardware tuning.
5. Merge to `main`, tag the manifest version (for example `v0.7.0`), and create a
   GitHub Release from the matching changelog section.
