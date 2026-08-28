#!/usr/bin/env bash
set -euo pipefail

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

jq -e '
  .schemaVersion == 1 and
  .id == "io.github.gustavonline.local-ai" and
  .name == "Local AI" and
  .version == "0.9.0" and
  (.kinds | index("bar-widget")) != null and
  .entryPoints.barWidget == "Panel.qml"
' "$plugin_dir/manifest.json" >/dev/null

bash -n "$plugin_dir/local-ai-control"
python3 -m py_compile "$plugin_dir/local-ai-copilot"
for file in "$plugin_dir/local-ai-control" "$plugin_dir/local-ai-copilot" "$plugin_dir/test.sh" \
  "$plugin_dir/tests/fake-pi" "$plugin_dir/tests/fake-hyprctl" "$plugin_dir/tests/fake-systemctl"; do
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

# Exercise the optional Copilot subsystem independently from the runtime
# controller. All model, Hyprland, Pi, and systemd dependencies are fake.
copilot_root="$test_root/copilot"
mkdir -p "$copilot_root"
mkdir -p "$copilot_root/bin"
ln -s "$plugin_dir/tests/fake-pi" "$copilot_root/bin/codex"
mkdir -p "$copilot_root/data/applications"
cat >"$copilot_root/data/applications/example-secret.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Example Secret
Exec=/usr/bin/example-secret
StartupWMClass=org.example.Secret
EOF
cat >"$copilot_root/data/applications/bitwarden.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Bitwarden
Exec=/usr/bin/bitwarden
StartupWMClass=bitwarden
EOF
port_file="$copilot_root/port"
python3 "$plugin_dir/tests/fake-openai-server.py" "$port_file" &
server_pid=$!
for _ in $(seq 1 50); do [[ -s $port_file ]] && break; sleep 0.05; done
[[ -s $port_file ]]
port=$(<"$port_file")

copilot_config="$copilot_root/config.toml"
sed \
  -e "s#http://127.0.0.1:8080/v1#http://127.0.0.1:${port}/v1#" \
  -e 's#command = \["pi-worker", "--profile", "inspect", "--thinking", "low", "--no-web", "--"\]#command = []#' \
  -e 's#launch_in_terminal = true#launch_in_terminal = false#' \
  -e "s#~/.config/omarchy/local-ai-copilot-playbook.json#${copilot_root}/playbook.json#" \
  "$plugin_dir/local-ai-copilot.example.toml" >"$copilot_config"

export LOCAL_AI_COPILOT_STATE_DIR="$copilot_root/state"
export LOCAL_AI_COPILOT_PI_DIR="$copilot_root/pi"
export LOCAL_AI_COPILOT_UNIT_DIR="$copilot_root/units"
export LOCAL_AI_COPILOT_PI="$plugin_dir/tests/fake-pi"
export LOCAL_AI_COPILOT_HYPRCTL="$plugin_dir/tests/fake-hyprctl"
export LOCAL_AI_COPILOT_SYSTEMCTL="$plugin_dir/tests/fake-systemctl"
export XDG_DATA_HOME="$copilot_root/data"
export PATH="$copilot_root/bin:$PATH"

model_choice="http://127.0.0.1:${port}/v1|test-local-model"
"$plugin_dir/local-ai-copilot" --config "$copilot_config" setup-state | jq -e \
  --arg choice "$model_choice" '
  .configured and
  (.modelChoices | map(.value) | index($choice)) != null and
  (.harnessChoices | map(.value) | index("codex")) != null
' >/dev/null
"$plugin_dir/local-ai-copilot" --config "$copilot_config" configure \
  "$model_choice" 0.82 false '["org.example.Secret|example-secret"]' codex >/dev/null
"$plugin_dir/local-ai-copilot" --config "$copilot_config" setup-state | jq -e \
  --arg choice "$model_choice" '
  .config.modelChoice == $choice and
  .config.minimumConfidence == 0.82 and
  (.config.shareWindowTitle | not) and
  .config.blockedApps == ["org.example.Secret|example-secret"] and
  .config.preferredHarness == "codex"
' >/dev/null
"$plugin_dir/local-ai-copilot" --config "$copilot_config" status | jq -e '
  .delegateAvailable and
  .preferredHarness == "codex" and
  .preferredHarnessLabel == "Codex" and
  (.harnessChoices | map(.value) | index("codex")) != null
' >/dev/null
"$plugin_dir/local-ai-copilot" --config "$copilot_config" apps | jq -e '
  (map(select(.value == "org.example.Secret|example-secret" and .label == "Example Secret")) | length == 1) and
  (map(select(.label == "Bitwarden")) | length == 0)
' >/dev/null

"$plugin_dir/local-ai-copilot" --config "$copilot_config" doctor --online | jq -e '
  .ok and .checks.runtime.ok and (.checks.runtime.detail | contains("32768 tokens"))
' >/dev/null
jq -e '
  .providers["copilot-local"].models[0] |
  .id == "test-local-model" and .contextWindow == 32768 and .maxTokens == 512
' "$copilot_root/pi/models.json" >/dev/null

context='{"appId":"org.example.App","title":"Example document","workspace":"1"}'
"$plugin_dir/local-ai-copilot" --config "$copilot_config" evaluate --context-json "$context" | jq -e '
  .title == "Prepare the next step" and .confidence == 0.91
' >/dev/null
jq -e '.id and .context.appId == "org.example.App"' "$copilot_root/state/suggestion.json" >/dev/null

"$plugin_dir/local-ai-copilot" --config "$copilot_config" delegate codex >/dev/null
jq -e 'length == 0' "$copilot_root/state/suggestion.json" >/dev/null
tail -n 1 "$copilot_root/state/audit.jsonl" | jq -e '
  .action == "delegated" and .harness == "codex"
' >/dev/null

"$plugin_dir/local-ai-copilot" --config "$copilot_config" evaluate --context-json "$context" >/dev/null
"$plugin_dir/local-ai-copilot" --config "$copilot_config" remember >/dev/null
jq -e '.version == 1 and (.rules | length) == 1' "$copilot_root/playbook.json" >/dev/null
"$plugin_dir/local-ai-copilot" --config "$copilot_config" test-suggestion >/dev/null
"$plugin_dir/local-ai-copilot" --config "$copilot_config" dismiss >/dev/null
jq -e 'length == 0' "$copilot_root/state/suggestion.json" >/dev/null

"$plugin_dir/local-ai-copilot" --config "$copilot_config" render-service | grep -Fq 'NoNewPrivileges=yes'
"$plugin_dir/local-ai-copilot" --config "$copilot_config" render-service | grep -Fq 'ProtectHome=read-only'
"$plugin_dir/local-ai-copilot" --config "$copilot_config" install-service >/dev/null
[[ -f $copilot_root/units/omarchy-local-ai-copilot.service ]]

grep -q 'id: suggestionWindow' "$plugin_dir/Panel.qml"
grep -q 'text: "ALWAYS-ON ASSISTANT"' "$plugin_dir/Panel.qml"
grep -q 'text: "LOCAL MODEL RUNTIME"' "$plugin_dir/Panel.qml"
grep -q 'label: "Always-on Assistant"' "$plugin_dir/Panel.qml"
grep -q 'text: root.settingsPage ? "Assistant settings" : "Local AI"' "$plugin_dir/Panel.qml"
grep -q 'label: "Blocked apps"' "$plugin_dir/Panel.qml"
grep -q 'label: "Preferred harness"' "$plugin_dir/Panel.qml"
grep -q '"Continue in…  ▾"' "$plugin_dir/Panel.qml"
grep -q 'WheelHandler {' "$plugin_dir/Panel.qml"
grep -q 'policy: ScrollBar.AlwaysOff' "$plugin_dir/Panel.qml"
grep -q 'WlrLayershell.keyboardFocus: WlrKeyboardFocus.None' "$plugin_dir/Panel.qml"
grep -q -- '--no-tools' "$plugin_dir/local-ai-copilot"
grep -q -- '--no-skills' "$plugin_dir/local-ai-copilot"
grep -q -- '--no-context-files' "$plugin_dir/local-ai-copilot"

if command -v omarchy >/dev/null; then
  omarchy plugin validate "$plugin_dir" >/dev/null
fi

printf 'Local AI runtime and Copilot checks passed\n'
