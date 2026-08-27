# Release checklist

1. Update `manifest.json` and `CHANGELOG.md` to the same semantic version.
2. Run `./test.sh` on a current Omarchy installation.
3. Install from a fresh clone and verify missing-config, ready-profile, start,
   switch, restart, stop, endpoint copy, and error-display behavior.
4. Confirm the repository contains no models, API keys, local TOML files,
   machine-specific services, or hardware tuning.
5. Merge to `main`, tag the manifest version (for example `v0.5.0`), and create a
   GitHub Release from the matching changelog section.
