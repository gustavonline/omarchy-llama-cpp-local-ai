#!/usr/bin/env bash
set -euo pipefail

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

jq -e '
  .schemaVersion == 1 and
  .id == "io.github.gustavonline.local-ai" and
  .name == "Local AI" and
  .version == "0.10.0" and
  (.kinds | index("bar-widget")) != null and
  .entryPoints.barWidget == "Panel.qml"
' "$plugin_dir/manifest.json" >/dev/null

bash -n "$plugin_dir/local-ai-control"
python3 -m py_compile "$plugin_dir/local-ai-assistant"
python3 -m py_compile "$plugin_dir/tests/benchmark-assistant-model.py"
for file in "$plugin_dir/local-ai-control" "$plugin_dir/local-ai-assistant" "$plugin_dir/test.sh" \
  "$plugin_dir/tests/fake-pi" "$plugin_dir/tests/fake-hyprctl" "$plugin_dir/tests/fake-systemctl" \
  "$plugin_dir/tests/fake-voxtype" "$plugin_dir/tests/fake-app" \
  "$plugin_dir/tests/fake-wl-copy"; do
  [[ -x $file ]] || { printf 'Expected executable: %s\n' "$file" >&2; exit 1; }
done
grep -qE 'id: feedbackClearTimer' "$plugin_dir/Panel.qml"
grep -qE 'function showTransientFeedback\(message\)' "$plugin_dir/Panel.qml"
grep -qE 'showTransientFeedback\("Endpoint copied"\)' "$plugin_dir/Panel.qml"
"$plugin_dir/local-ai-control" --config "$plugin_dir/local-ai.example.toml" status | jq -e '
  (.profile | type == "string") and
  (.state | type == "string") and
  (.endpoint | type == "string") and
  (.configFile | type == "string") and
  (.profiles | type == "array") and
  (all(.profiles[];
    (.id | type == "string") and
    (.model | type == "string") and
    (.variant | type == "string") and
    (.context | type == "string") and
    (.unitFile | type == "string") and
    (.ready | type == "boolean")
  ))
' >/dev/null

# Exercise start with both an explicit profile and the configured default.
# A fake systemctl keeps this test self-contained and prevents it from
# starting a real model during validation.
test_root=$(mktemp -d)
server_pid=""
cleanup() {
  if [[ -n $server_pid ]]; then kill "$server_pid" >/dev/null 2>&1 || true; fi
  rm -rf -- "$test_root"
}
trap cleanup EXIT
mkdir -p "$test_root/bin"
touch "$test_root/model-Q8_0.gguf"
cat >"$test_root/config.toml" <<'EOF'
default = "Test"

[[profiles]]
name = "Test"
service = "local-ai-test.service"
EOF
cat >"$test_root/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >>"$LOCAL_AI_TEST_LOG"
case " $* " in
  *" show "*)
    printf '{ path=/usr/bin/llama-server ; argv[]=/usr/bin/llama-server --model %s --host 127.0.0.1 --port 8080 --device Vulkan0 --ctx-size 65536 ; ignore_errors=no ; }\n' "$LOCAL_AI_TEST_MODEL"
    ;;
  *" cat "*) exit 0 ;;
  *" is-active "*)
    [[ " $* " == *" --quiet "* ]] && exit 3
    printf 'inactive\n'
    exit 3
    ;;
  *" is-failed "*) printf 'inactive\n'; exit 1 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$test_root/bin/systemctl"
export LOCAL_AI_TEST_LOG="$test_root/systemctl.log"
export LOCAL_AI_TEST_MODEL="$test_root/model-Q8_0.gguf"
PATH="$test_root/bin:$PATH" "$plugin_dir/local-ai-control" --config "$test_root/config.toml" start Test
PATH="$test_root/bin:$PATH" "$plugin_dir/local-ai-control" --config "$test_root/config.toml" start
grep -Fxq -- '--user start -- local-ai-test.service' "$LOCAL_AI_TEST_LOG"

# Runtime labels are presentation names rather than quantization identifiers.
# Renaming one must preserve its service and update the configured default.
rename_payload='[{"id":"Test","name":"Fast everyday model"}]'
PATH="$test_root/bin:$PATH" "$plugin_dir/local-ai-control" \
  --config "$test_root/config.toml" rename-profiles "$rename_payload"
python3 - "$test_root/config.toml" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as handle:
    config = tomllib.load(handle)
assert config["default"] == "Fast everyday model"
assert config["profiles"] == [{"name": "Fast everyday model", "service": "local-ai-test.service"}]
PY
PATH="$test_root/bin:$PATH" "$plugin_dir/local-ai-control" \
  --config "$test_root/config.toml" status | jq -e '
    .defaultProfile == "Fast everyday model" and
    .profiles[0].id == "Fast everyday model" and
    .profiles[0].label == "Fast everyday model"
' >/dev/null
PATH="$test_root/bin:$PATH" "$plugin_dir/local-ai-control" \
  --config "$test_root/config.toml" start "Fast everyday model"

if "$plugin_dir/local-ai-control" --config "$test_root/missing.toml" doctor 2>/dev/null; then
  printf 'doctor unexpectedly accepted a missing config\n' >&2
  exit 1
fi

printf 'default = ""\nprofiles = []\n' >"$test_root/empty.toml"
if "$plugin_dir/local-ai-control" --config "$test_root/empty.toml" doctor >/dev/null 2>&1; then
  printf 'doctor unexpectedly accepted an empty profile list\n' >&2
  exit 1
fi

printf '[[profiles]]\nname = "Unsafe"\nservice = "../unsafe.service"\n' >"$test_root/invalid.toml"
if "$plugin_dir/local-ai-control" --config "$test_root/invalid.toml" status >/dev/null 2>&1; then
  printf 'status unexpectedly accepted an invalid service name\n' >&2
  exit 1
fi

# Exercise the optional Assistant subsystem independently from the runtime
# controller. All model, Hyprland, Pi, and systemd dependencies are fake.
assistant_root="$test_root/assistant"
mkdir -p "$assistant_root"
mkdir -p "$assistant_root/bin"
ln -s "$plugin_dir/tests/fake-pi" "$assistant_root/bin/codex"
ln -s "$plugin_dir/tests/fake-pi" "$assistant_root/bin/pi-worker"
ln -s "$plugin_dir/tests/fake-app" "$assistant_root/bin/omarchy"
mkdir -p "$assistant_root/data/applications"
cat >"$assistant_root/data/applications/example-secret.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Example Secret
Exec=/usr/bin/example-secret
StartupWMClass=org.example.Secret
EOF
cat >"$assistant_root/data/applications/bitwarden.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Bitwarden
Exec=/usr/bin/bitwarden
StartupWMClass=bitwarden
EOF
port_file="$assistant_root/port"
python3 "$plugin_dir/tests/fake-openai-server.py" "$port_file" &
server_pid=$!
for _ in $(seq 1 50); do [[ -s $port_file ]] && break; sleep 0.05; done
[[ -s $port_file ]]
port=$(<"$port_file")

assistant_config="$assistant_root/config.toml"
sed \
  -e "s#http://127.0.0.1:8080/v1#http://127.0.0.1:${port}/v1#" \
  -e 's#command = \["pi-worker", "--profile", "inspect", "--thinking", "low", "--no-web", "--text", "--"\]#command = []#' \
  -e 's#launch_in_terminal = true#launch_in_terminal = false#' \
  -e "s#~/.config/omarchy/local-ai-assistant-playbook.json#${assistant_root}/playbook.json#" \
  "$plugin_dir/local-ai.example.toml" >"$assistant_config"

export LOCAL_AI_ASSISTANT_STATE_DIR="$assistant_root/state"
export LOCAL_AI_ASSISTANT_HANDOFFS_DIR="$assistant_root/handoffs"
export LOCAL_AI_ASSISTANT_PI_DIR="$assistant_root/pi"
export LOCAL_AI_ASSISTANT_UNIT_DIR="$assistant_root/units"
export LOCAL_AI_ASSISTANT_PI="$plugin_dir/tests/fake-pi"
export LOCAL_AI_ASSISTANT_HYPRCTL="$plugin_dir/tests/fake-hyprctl"
export LOCAL_AI_ASSISTANT_SYSTEMCTL="$plugin_dir/tests/fake-systemctl"
export LOCAL_AI_ASSISTANT_VOXTYPE="$plugin_dir/tests/fake-voxtype"
export LOCAL_AI_ASSISTANT_VOXTYPE_STATE="$assistant_root/voxtype-state"
export LOCAL_AI_ASSISTANT_VOXTYPE_LOG="$assistant_root/voxtype.log"
export LOCAL_AI_ASSISTANT_FAKE_FOCUSED="$assistant_root/focused"
export LOCAL_AI_ASSISTANT_FAKE_WINDOW_LOG="$assistant_root/window.log"
export LOCAL_AI_ASSISTANT_CODEX_APP="$plugin_dir/tests/fake-app codex"
export LOCAL_AI_ASSISTANT_FAKE_APP_LOG="$assistant_root/app.log"
export LOCAL_AI_ASSISTANT_CLIPBOARD="$plugin_dir/tests/fake-wl-copy"
export LOCAL_AI_ASSISTANT_FAKE_CLIPBOARD="$assistant_root/clipboard"
export LOCAL_AI_ASSISTANT_VOXTYPE_OSD_PIDS=""
export LOCAL_AI_ASSISTANT_RUNTIME_DIR="$assistant_root/runtime"
export LOCAL_AI_ASSISTANT_FAKE_HYPR_RUNTIME="$LOCAL_AI_ASSISTANT_RUNTIME_DIR"
export LOCAL_AI_ASSISTANT_FAKE_HYPR_SIGNATURE="test-signature"
export LOCAL_AI_ASSISTANT_FAKE_REQUIRE_HYPR_ENV=1
export XDG_DATA_HOME="$assistant_root/data"
export PATH="$assistant_root/bin:$PATH"
mkdir -p "$LOCAL_AI_ASSISTANT_RUNTIME_DIR/hypr/$LOCAL_AI_ASSISTANT_FAKE_HYPR_SIGNATURE"
printf '%s\nwayland-test\n' "$$" > \
  "$LOCAL_AI_ASSISTANT_RUNTIME_DIR/hypr/$LOCAL_AI_ASSISTANT_FAKE_HYPR_SIGNATURE/hyprland.lock"
touch "$LOCAL_AI_ASSISTANT_RUNTIME_DIR/hypr/$LOCAL_AI_ASSISTANT_FAKE_HYPR_SIGNATURE/.socket.sock"
touch "$LOCAL_AI_ASSISTANT_RUNTIME_DIR/hypr/$LOCAL_AI_ASSISTANT_FAKE_HYPR_SIGNATURE/.socket2.sock"
printf 'idle\n' >"$LOCAL_AI_ASSISTANT_VOXTYPE_STATE"

model_choice="http://127.0.0.1:${port}/v1|test-local-model"
"$plugin_dir/local-ai-assistant" --config "$assistant_config" setup-state | jq -e \
  --arg choice "$model_choice" '
  .configured and
  (.modelChoices | map(.value) | index($choice)) != null and
  .config.preferredHarness == "codex" and
  (.harnessChoices | map(.value) | index("codex")) != null and
  (.harnessChoices | map(.value) | index("auto")) == null
' >/dev/null
grep -Fq 'No learned dismissals yet.' "$assistant_root/state/memory.md"
"$plugin_dir/local-ai-assistant" --config "$assistant_config" open-memory >/dev/null
grep -Fq "launch config editor $assistant_root/state/memory.md" "$LOCAL_AI_ASSISTANT_FAKE_APP_LOG"
"$plugin_dir/local-ai-assistant" --config "$assistant_config" configure \
  "$model_choice" 0.62 false '["org.example.Secret|example-secret"]' codex >/dev/null
"$plugin_dir/local-ai-assistant" --config "$assistant_config" setup-state | jq -e \
  --arg choice "$model_choice" '
  .config.modelChoice == $choice and
  .config.minimumConfidence == 0.62 and
  (.config.shareWindowTitle | not) and
  .config.blockedApps == ["org.example.Secret|example-secret"] and
  .config.preferredHarness == "codex"
' >/dev/null
python3 - "$assistant_config" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as handle:
    observer = tomllib.load(handle)["assistant"]["observer"]
assert observer["minimum_confidence"] == 0.62
assert observer["debounce_sec"] == 2
assert observer["cooldown_sec"] == 120
assert observer["poll_interval_sec"] == 8
assert observer["max_suggestions_per_hour"] == 8
PY
"$plugin_dir/local-ai-assistant" --config "$assistant_config" status | jq -e '
  .delegateAvailable and
  .preferredHarness == "codex" and
  .preferredHarnessLabel == "Codex" and
  (.harnessChoices | map(.value) | index("codex")) != null
' >/dev/null
"$plugin_dir/local-ai-assistant" --config "$assistant_config" apps | jq -e '
  (map(select(.value == "org.example.Secret|example-secret" and .label == "Example Secret")) | length == 1) and
  (map(select(.label == "Bitwarden")) | length == 0)
' >/dev/null

"$plugin_dir/local-ai-assistant" --config "$assistant_config" doctor --online | jq -e '
  .ok and .checks.runtime.ok and (.checks.runtime.detail | contains("32768 tokens"))
' >/dev/null
jq -e '
  .providers["assistant-local"].models[0] |
  .id == "test-local-model" and .contextWindow == 32768 and .maxTokens == 512
' "$assistant_root/pi/models.json" >/dev/null

context='{"appId":"org.example.App","title":"Project roadmap document","workspace":"1"}'
"$plugin_dir/local-ai-assistant" --config "$assistant_config" evaluate --context-json "$context" | jq -e '
  .title == "Prepare the next step" and .confidence == 0.91
' >/dev/null
jq -e '.id and .context.appId == "org.example.App" and (.observation | length > 0)' "$assistant_root/state/suggestion.json" >/dev/null

# Generic entertainment/browser metadata is rejected before inference, even in
# Proactive mode. This prevents small-model confidence from turning filler into
# interruptions.
youtube_context='{"appId":"zen-browser","title":"YouTube — Zen Browser","workspace":"1"}'
"$plugin_dir/local-ai-assistant" --config "$assistant_config" evaluate --context-json "$youtube_context" | jq -e 'length == 0' >/dev/null
jq -e 'length == 0' "$assistant_root/state/suggestion.json" >/dev/null

"$plugin_dir/local-ai-assistant" --config "$assistant_config" evaluate --context-json "$context" >/dev/null
codex_handoff=$("$plugin_dir/local-ai-assistant" --config "$assistant_config" delegate)
jq -e 'length == 0' "$assistant_root/state/suggestion.json" >/dev/null
tail -n 1 "$assistant_root/state/audit.jsonl" | jq -e '
  .action == "delegated" and .harness == "codex" and (.handoffPath | endswith("/SESSION.md"))
' >/dev/null
[[ -f $codex_handoff && $codex_handoff == "$assistant_root"/handoffs/*/SESSION.md ]]
[[ $(<"$LOCAL_AI_ASSISTANT_FAKE_CLIPBOARD") == "$codex_handoff" ]]
[[ $(stat -c '%a' "$(dirname -- "$codex_handoff")") == 700 ]]
[[ $(stat -c '%a' "$codex_handoff") == 600 ]]
[[ $(stat -c '%a' "$(dirname -- "$codex_handoff")/session.json") == 600 ]]
jq -e --arg handoff "$codex_handoff" '
  .schemaVersion == 1 and .kind == "local-ai-handoff" and
  .intendedHarness == "codex" and .source.application == "Local AI" and
  .assistant.response == "A bounded local suggestion from the fake Pi runtime." and
  (.workingDirectory | type == "string")
' "$(dirname -- "$codex_handoff")/session.json" >/dev/null
grep -Fq '# Local AI handoff session' "$codex_handoff"
grep -Fxq 'codex' "$LOCAL_AI_ASSISTANT_FAKE_APP_LOG"

# Pi Worker v0.6 handoff receives an explicit project root, stable job ID, and
# final-text output while retaining the bounded inspect profile.
mkdir -p "$assistant_root/project"
export LOCAL_AI_ASSISTANT_WORKING_DIRECTORY="$assistant_root/project"
export LOCAL_AI_ASSISTANT_FAKE_PI_ARGV_LOG="$assistant_root/pi-worker-argv.log"
"$plugin_dir/local-ai-assistant" --config "$assistant_config" configure \
  "$model_choice" 0.62 false '["org.example.Secret|example-secret"]' pi-worker >/dev/null
"$plugin_dir/local-ai-assistant" --config "$assistant_config" evaluate --context-json "$context" >/dev/null
"$plugin_dir/local-ai-assistant" --config "$assistant_config" delegate >/dev/null
for _ in $(seq 1 40); do [[ -s $LOCAL_AI_ASSISTANT_FAKE_PI_ARGV_LOG ]] && break; sleep 0.01; done
grep -Fq -- '--profile inspect' "$LOCAL_AI_ASSISTANT_FAKE_PI_ARGV_LOG"
grep -Fq -- "--cwd ${assistant_root}/project" "$LOCAL_AI_ASSISTANT_FAKE_PI_ARGV_LOG"
grep -Eq -- '--job-id local-ai-[A-Za-z0-9_-]+' "$LOCAL_AI_ASSISTANT_FAKE_PI_ARGV_LOG"
grep -Fq -- '--text' "$LOCAL_AI_ASSISTANT_FAKE_PI_ARGV_LOG"
grep -Eq -- "$assistant_root/handoffs/[A-Za-z0-9_-]+/SESSION.md" "$LOCAL_AI_ASSISTANT_FAKE_PI_ARGV_LOG"
unset LOCAL_AI_ASSISTANT_FAKE_PI_ARGV_LOG
"$plugin_dir/local-ai-assistant" --config "$assistant_config" configure \
  "$model_choice" 0.62 false '["org.example.Secret|example-secret"]' codex >/dev/null

"$plugin_dir/local-ai-assistant" --config "$assistant_config" evaluate --context-json "$context" >/dev/null
"$plugin_dir/local-ai-assistant" --config "$assistant_config" remember >/dev/null
jq -e '.version == 1 and (.rules | length) == 1' "$assistant_root/playbook.json" >/dev/null
"$plugin_dir/local-ai-assistant" --config "$assistant_config" test-suggestion >/dev/null
jq -e '.title == "A useful next step" and (.observation | startswith("Demo:"))' "$assistant_root/state/suggestion.json" >/dev/null
"$plugin_dir/local-ai-assistant" --config "$assistant_config" hold-suggestion >/dev/null
jq -e '.held == true' "$assistant_root/state/suggestion.json" >/dev/null
"$plugin_dir/local-ai-assistant" --config "$assistant_config" release-suggestion >/dev/null
jq -e '.held == false and .expiresAt > now' "$assistant_root/state/suggestion.json" >/dev/null
"$plugin_dir/local-ai-assistant" --config "$assistant_config" dismiss >/dev/null

# SUPER+A is a true hold-to-talk interaction. Voxtype writes to a private file;
# Local AI reads it directly, so no text or Enter key can leak into another app.
rm -f -- "$LOCAL_AI_ASSISTANT_FAKE_FOCUSED"
"$plugin_dir/local-ai-assistant" --config "$assistant_config" voice-start >/dev/null
[[ ! -e $LOCAL_AI_ASSISTANT_FAKE_FOCUSED ]]
# Hyprland may emit repeated key-down events while the chord remains held. A
# duplicate start must neither replace the current session nor start Voxtype twice.
voice_session_id=$(jq -r .sessionId "$assistant_root/state/voice-control.json")
"$plugin_dir/local-ai-assistant" --config "$assistant_config" voice-start >/dev/null
[[ $(jq -r .sessionId "$assistant_root/state/voice-control.json") == "$voice_session_id" ]]
jq -e '
  .mode == "voice" and (.awaitingInput | not) and .held and (.focusPending | not)
' "$assistant_root/state/suggestion.json" >/dev/null
jq -e '.pressed and .startDone and .phase == "recording"' \
  "$assistant_root/state/voice-control.json" >/dev/null
[[ $(<"$LOCAL_AI_ASSISTANT_VOXTYPE_STATE") == recording ]]
"$plugin_dir/local-ai-assistant" --config "$assistant_config" voice-stop >/dev/null
[[ ! -e $LOCAL_AI_ASSISTANT_FAKE_FOCUSED ]]
for _ in $(seq 1 40); do [[ $(<"$LOCAL_AI_ASSISTANT_VOXTYPE_STATE") == idle ]] && break; sleep 0.01; done
[[ $(<"$LOCAL_AI_ASSISTANT_VOXTYPE_STATE") == idle ]]
jq -e '(.pressed | not) and .startDone and .phase == "idle"' \
  "$assistant_root/state/voice-control.json" >/dev/null
grep -Eq -- '^record start --file=.*/voice-transcript-[^/]+\.txt --no-auto-submit$' \
  "$LOCAL_AI_ASSISTANT_VOXTYPE_LOG"
grep -Fxq -- 'record stop' "$LOCAL_AI_ASSISTANT_VOXTYPE_LOG"
jq -e '
  .mode == "direct" and (.awaitingInput | not) and (.streaming | not) and
  (.held | not) and .request == "Summarize the next step" and
  .body == "Streaming local response." and .copyText == .body
' "$assistant_root/state/suggestion.json" >/dev/null
if compgen -G "$assistant_root/state/voice-transcript-*.txt" >/dev/null; then
  printf 'Private voice transcript was not cleaned up\n' >&2
  exit 1
fi

# A completed release must rearm the next voice turn without duplicating its
# recording, transcription, or submit events.
"$plugin_dir/local-ai-assistant" --config "$assistant_config" voice-start >/dev/null
second_voice_session_id=$(jq -r .sessionId "$assistant_root/state/voice-control.json")
[[ $second_voice_session_id != "$voice_session_id" ]]
"$plugin_dir/local-ai-assistant" --config "$assistant_config" voice-stop >/dev/null
[[ $(grep -Ec -- '^record start --file=.*/voice-transcript-[^/]+\.txt --no-auto-submit$' "$LOCAL_AI_ASSISTANT_VOXTYPE_LOG") -eq 2 ]]
[[ $(grep -Fxc -- 'record stop' "$LOCAL_AI_ASSISTANT_VOXTYPE_LOG") -eq 2 ]]
"$plugin_dir/local-ai-assistant" --config "$assistant_config" dismiss >/dev/null
jq -e 'length == 0' "$assistant_root/state/suggestion.json" >/dev/null

# Dismiss learns the generated suggestion pattern in its app/page context. It
# stores normalized scope tags in a separate private memory, never the raw
# window title in the audit log.
"$plugin_dir/local-ai-assistant" --config "$assistant_config" evaluate --context-json "$context" >/dev/null
"$plugin_dir/local-ai-assistant" --config "$assistant_config" dismiss >/dev/null
"$plugin_dir/local-ai-assistant" --config "$assistant_config" evaluate --context-json "$context" | jq -e 'length == 0' >/dev/null
if grep -Fq 'Project roadmap document' "$assistant_root/state/audit.jsonl"; then
  printf 'Audit log leaked a window title\n' >&2
  exit 1
fi
jq -e '
  .examples | any(
    .title == "Prepare the next step" and
    (.scopes | any(.appId == "org.example.app" and (.tags | index("project")) != null))
  )
' "$assistant_root/state/dismissed-suggestions.json" >/dev/null
grep -Fq -- '- **Avoid suggesting: Prepare the next step**' "$assistant_root/state/memory.md"
grep -Fq -- '  - Learning level: App/context specific' "$assistant_root/state/memory.md"
grep -Fq -- '`org.example.app`' "$assistant_root/state/memory.md"

# The same suggestion remains eligible in a genuinely different context once;
# after it is rejected across two distinct scopes it becomes a global negative
# preference until the 30-day memory expires or the user resets it.
other_context='{"appId":"org.other.Editor","title":"Quarterly budget review","workspace":"2"}'
"$plugin_dir/local-ai-assistant" --config "$assistant_config" evaluate --context-json "$other_context" | jq -e '.title == "Prepare the next step"' >/dev/null
"$plugin_dir/local-ai-assistant" --config "$assistant_config" dismiss >/dev/null
global_context='{"appId":"org.third.Editor","title":"Release notes review","workspace":"3"}'
"$plugin_dir/local-ai-assistant" --config "$assistant_config" evaluate --context-json "$global_context" | jq -e 'length == 0' >/dev/null
jq -e '.examples | map(select(.title == "Prepare the next step"))[0].scopes | length == 2' \
  "$assistant_root/state/dismissed-suggestions.json" >/dev/null
grep -Fq -- '  - Learning level: Global across contexts' "$assistant_root/state/memory.md"
"$plugin_dir/local-ai-assistant" --config "$assistant_config" clear-feedback >/dev/null
jq -e '.examples | length == 0' "$assistant_root/state/dismissed-suggestions.json" >/dev/null
grep -Fq 'No learned dismissals yet.' "$assistant_root/state/memory.md"

"$plugin_dir/local-ai-assistant" --config "$assistant_config" prepare-window >/dev/null
"$plugin_dir/local-ai-assistant" --config "$assistant_config" place-window >/dev/null
grep -Fq 'hl.dsp.window.move({ x = 1236, y = 656, relative = false, window = "address:0x123abc" })' \
  "$LOCAL_AI_ASSISTANT_FAKE_WINDOW_LOG"
"$plugin_dir/local-ai-assistant" --config "$assistant_config" summon >/dev/null
jq -e '
  .mode == "summon" and .awaitingInput and .held and (.focusPending | not) and
  .title == "Ask Local AI"
' "$assistant_root/state/suggestion.json" >/dev/null
"$plugin_dir/local-ai-assistant" --config "$assistant_config" ask "Summarize the next step" >/dev/null
jq -e '
  .mode == "summon" and (.awaitingInput | not) and (.streaming | not) and
  .body == "Streaming local response." and .copyText == .body and
  (.delegatePrompt | contains("Summarize the next step"))
' "$assistant_root/state/suggestion.json" >/dev/null
"$plugin_dir/local-ai-assistant" --config "$assistant_config" dismiss >/dev/null

"$plugin_dir/local-ai-assistant" --config "$assistant_config" render-service | grep -Fq 'NoNewPrivileges=yes'
"$plugin_dir/local-ai-assistant" --config "$assistant_config" render-service | grep -Fq 'ProtectHome=read-only'
"$plugin_dir/local-ai-assistant" --config "$assistant_config" install-service >/dev/null
[[ -f $assistant_root/units/omarchy-local-ai-assistant.service ]]

grep -q 'id: suggestionWindow' "$plugin_dir/Panel.qml"
grep -q 'text: "ALWAYS-ON ASSISTANT"' "$plugin_dir/Panel.qml"
grep -q 'text: "LOCAL MODEL RUNTIME"' "$plugin_dir/Panel.qml"
grep -q 'label: "Always-on Assistant"' "$plugin_dir/Panel.qml"
grep -q 'text: root.settingsPage ? "Assistant settings" : "Local AI"' "$plugin_dir/Panel.qml"
grep -q 'label: "Blocked apps"' "$plugin_dir/Panel.qml"
grep -q 'label: "Preferred harness"' "$plugin_dir/Panel.qml"
grep -q 'text: "View memory"' "$plugin_dir/Panel.qml"
grep -q 'text: "Reset · " + root.learnedDismissalCount' "$plugin_dir/Panel.qml"
grep -q 'bordered: true' "$plugin_dir/Panel.qml"
grep -q 'return label === "" ? "Continue" : "Continue in " + label' "$plugin_dir/Panel.qml"
grep -q 'return "Dismiss · " + remaining + "s"' "$plugin_dir/Panel.qml"
grep -q 'return "Dismiss · paused"' "$plugin_dir/Panel.qml"
if grep -q 'harnessMenuOpen' "$plugin_dir/Panel.qml"; then
  printf 'Suggestion card still contains the harness dropdown state\n' >&2
  exit 1
fi
grep -q 'WheelHandler {' "$plugin_dir/Panel.qml"
grep -q 'policy: ScrollBar.AlwaysOff' "$plugin_dir/Panel.qml"
grep -q 'FloatingWindow {' "$plugin_dir/Panel.qml"
grep -q 'title: "Local AI Suggestion"' "$plugin_dir/Panel.qml"
grep -q 'visible: root.suggestionVisible && root.suggestionWindowPrepared && !root.voiceMode' "$plugin_dir/Panel.qml"
grep -q 'iconComponent: root.voiceMode ? voiceIndicatorComponent : null' "$plugin_dir/Panel.qml"
grep -q '"place-window"' "$plugin_dir/Panel.qml"
grep -q 'maximumLineCount: root.suggestionInteracting ? 1000 : 9' "$plugin_dir/Panel.qml"
grep -q 'tooltipText: "Copy response"' "$plugin_dir/Panel.qml"
grep -q 'anchors.bottom: actionFooter.top' "$plugin_dir/Panel.qml"
grep -q 'anchors.bottom: parent.bottom' "$plugin_dir/Panel.qml"
if grep -q 'text: "Copy draft"\|text: "Remember"' "$plugin_dir/Panel.qml"; then
  printf 'Suggestion card still exposes legacy primary actions\n' >&2
  exit 1
fi
grep -q 'Window.onActiveChanged:' "$plugin_dir/Panel.qml"
grep -q 'hold-suggestion' "$plugin_dir/Panel.qml"
grep -q 'id: summonField' "$plugin_dir/Panel.qml"
if grep -q 'id: voiceWindow\|id: voiceField\|title: "Local AI Voice"' "$plugin_dir/Panel.qml"; then
  echo "legacy floating voice UI remains" >&2
  exit 1
fi
grep -q 'voxtype-audio-bridge' "$plugin_dir/Panel.qml"
grep -q 'root.dictationRecording && root.voiceMode' "$plugin_dir/Panel.qml"
grep -q 'text: root.voiceMode ? "" : "󰍛"' "$plugin_dir/Panel.qml"
grep -q 'function voiceBarHeight(index)' "$plugin_dir/Panel.qml"
grep -q 'id: voxtypeStateFile' "$plugin_dir/Panel.qml"
grep -q 'runAssistantAction("ask", request)' "$plugin_dir/Panel.qml"
grep -q 'streaming === true' "$plugin_dir/Panel.qml"
if grep -q 'text: "Edit names"' "$plugin_dir/Panel.qml"; then
  printf 'Runtime panel still exposes the inline Edit names action\n' >&2
  exit 1
fi
grep -q 'text: "Open full Local AI config"' "$plugin_dir/Panel.qml"
grep -Fq 'openConfigProcess.command = ["omarchy", "launch", "config", "editor", path]' "$plugin_dir/Panel.qml"
if grep -q 'runtimeNamesEditing\|runtimeNameModel\|pendingAction = "rename-profiles"' "$plugin_dir/Panel.qml"; then
  printf 'Dead inline runtime-name editor state remains in the panel\n' >&2
  exit 1
fi
if grep -q 'text: "󰚩"' "$plugin_dir/Panel.qml"; then
  printf 'Suggestion card still contains the agent icon\n' >&2
  exit 1
fi
if grep -qE 'text: "(Observed|Suggestion)"' "$plugin_dir/Panel.qml"; then
  printf 'Suggestion card still contains redundant section headings\n' >&2
  exit 1
fi
grep -q 'no_initial_focus = true' "$plugin_dir/local-ai-assistant"
grep -q -- '--no-tools' "$plugin_dir/local-ai-assistant"
grep -q -- '--no-skills' "$plugin_dir/local-ai-assistant"
grep -q -- '--no-context-files' "$plugin_dir/local-ai-assistant"

qml_lint=$(command -v qmllint || true)
if [[ -z $qml_lint && -x /usr/lib/qt6/bin/qmllint ]]; then
  qml_lint=/usr/lib/qt6/bin/qmllint
fi
if [[ -n $qml_lint ]]; then
  qml_output=$($qml_lint "$plugin_dir/Panel.qml" 2>&1 || true)
  if grep -q '\[syntax\]' <<<"$qml_output"; then
    printf '%s\n' "$qml_output" >&2
    exit 1
  fi
fi

if command -v omarchy >/dev/null; then
  omarchy plugin validate "$plugin_dir" >/dev/null
fi

printf 'Local AI runtime and Assistant checks passed\n'
