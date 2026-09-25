# Changelog

## 0.10.0 — 2026-09-02

- Consolidate runtime and Assistant settings in `local-ai.toml`, preserve Assistant settings when renaming profiles, and align docs and tests with the shared configuration and current UI.

- Replace the suggestion-card harness chooser with one direct **Continue in
  [preferred harness]** button and a small Settings provenance label
- Resolve legacy automatic harness preferences to an installed default while
  requiring one concrete preferred harness when Settings are saved
- Turn suggestions into compact 340×320 floating windows that open unfocused,
  participate in normal window switching, and remain open while hovered or focused
- Restart the 30-second expiry only after the suggestion loses both hover and focus
- Show the remaining auto-close time inside Dismiss and mark it paused while
  the suggestion is hovered or focused
- Reduce the card to one compact context line and response, removing the agent
  icon, confidence display, and redundant Observed/Suggestion headings
- Move explicit voice feedback into the existing Local AI bar icon: a blue live
  waveform while recording and a light pulse while transcribing, with no second
  icon or voice window
- Turn `SUPER + A` into a repeat-safe hold-to-talk flow: key-down starts Voxtype,
  key-up transcribes to a private per-turn file and submits once without typing
  text or Enter into the focused application
- Stream local Pi output into the unfocused bottom-right response surface and
  retain dismiss, contextual copy, and preferred-harness continuation actions
- Keep the bar slot alive with a real waveform icon component throughout
  recording/transcription, and re-place the persistent Quickshell suggestion
  surface at the active monitor's bottom-right corner whenever it appears
- Reduce completed suggestion cards to **Dismiss** and **Continue in…**; reveal
  a small non-closing copy control plus the complete scrollable response only
  while the card is hovered or keyboard-focused; anchor primary actions at the
  card bottom and place copy after the rendered response at its lower right
- Make Continue create a new private, harness-neutral handoff session with
  `SESSION.md` and `session.json`, copy only the Markdown path, and open the
  Codex desktop app without automatically pasting or submitting a prompt
- Update Pi Worker delegation for v0.6 with the captured working directory,
  stable job IDs, explicit final-text output, and progressive skill discovery
- Support free-form display names from the advanced runtime config while keeping
  model, quantization, context, and service details unchanged
- Separate runtime identity from engine implementation: generic llama.cpp slots
  can point at Qwen, Gemma, or another GGUF, while quantization is discovered
  technical metadata rather than a runtime name
- Make **Proactive** a full behavior preset: two-second debounce, eight-second
  fallback polling, 120-second context cooldown, eight suggestions per hour, and
  mode-aware local-model guidance
- Add deterministic pre/post-inference actionability gates and a private
  30-day dismissal memory scoped to suggestion pattern plus normalized app/page
  context; two cross-context dismissals promote a pattern to a global preference
- Add **Reset learned dismissals** to Assistant Settings
- Make every dismissal add or strengthen a human-readable point in the private
  `memory.md`, and add **View learned memory** beside the reset action
- Discover the active Hyprland IPC runtime automatically so the always-on
  systemd service can use `hyprctl` after login without inherited shell variables
- Standardize feature, command, config, prompt, state, and service naming on
  **Always-on Assistant** throughout the plugin
- Consolidate direct chat and proactive guidance into one explicit, mode-aware
  assistant system prompt; keep `memory.md` as readable learned state rather than
  treating it as an additional prompt or loading ambient `AGENTS.md` files
- Add a repeatable local-model decision benchmark and strengthen playbook-backed
  actionability while keeping passive video and generic browser contexts silent

## 0.9.0 — 2026-08-28

- Add a native **Preferred harness** setting with automatic discovery of Codex,
  Claude Code, Gemini CLI, Pi Worker, Pi, and an optional custom adapter
- Replace the generic Delegate action with an explicit **Continue in…** chooser
  on each suggestion; the configured default is highlighted without hiding the
  other installed harnesses
- Keep every handoff user-approved, open it visibly in a terminal, and record
  the chosen harness in the metadata-only audit log
- Hide the panel's visual scrollbar while preserving mouse-wheel, touchpad, and
  drag scrolling across the full panel
- Reframe acceptance testing around normal work and real local inference; keep
  the synthetic suggestion command as a developer-only regression fixture

## 0.8.0 — 2026-08-28

- Standardize the public feature name as **Always-on Assistant** while keeping
  the existing implementation identifiers stable for that release
- Add a Local Transcript-style installed-app picker for extra privacy blocks;
  the built-in password-manager and sensitive-title protections remain fixed
- Make mouse-wheel scrolling work across the whole panel, including its header,
  and reset the scroll position when navigating between the main and settings pages
- Add a practical manual acceptance guide covering quietness, privacy, lifecycle,
  synthetic suggestions, explicit delegation, and current limitations
- Verify compatibility with local-ai-pi-worker v0.4 and make its safe read-only
  `inspect` delegation profile explicit in the example configuration

## 0.7.0 — 2026-08-28

- Simplify the main panel around one always-on Assistant toggle and one settings
  action, removing pause, restart, playbook, and test controls from the normal UI
- Put Assistant first and keep runtime profiles, endpoint actions, and model
  controls together in the lower Local AI section
- Add a Local Transcript-inspired settings page with back navigation, native
  model/frequency dropdowns, window-title privacy toggle, and save feedback
- Discover compatible models from active local Ollama and llama.cpp endpoints
  and identify the smallest available model for the lightweight Assistant
- Preserve the advanced TOML editor for uncommon endpoint, startup, delegation,
  privacy, and rate-limit configuration

## 0.6.0 — 2026-08-28

- Add the opt-in always-on local Assistant inside the existing Local AI dropdown
  instead of creating a second Omarchy plugin or menubar icon
- Add an event-driven, privacy-filtered Hyprland observer backed by a minimal
  isolated Pi session and a configurable local OpenAI-compatible endpoint
- Add non-focus-stealing bottom-right suggestions with dismiss, copy, remember,
  and explicit optional heavy-harness delegation actions
- Add private machine-local Assistant settings, editable playbook memory,
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
