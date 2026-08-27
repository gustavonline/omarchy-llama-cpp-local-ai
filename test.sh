#!/usr/bin/env bash
set -euo pipefail

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

jq -e '
  .schemaVersion == 1 and
  .id == "io.github.gustavonline.local-ai" and
  .name == "Local AI" and
  .version == "0.5.0" and
  (.kinds | index("bar-widget")) != null and
  .entryPoints.barWidget == "Panel.qml"
' "$plugin_dir/manifest.json" >/dev/null

bash -n "$plugin_dir/local-ai-control"
rg -q 'id: feedbackClearTimer' "$plugin_dir/Panel.qml"
rg -q 'function showTransientFeedback\(message\)' "$plugin_dir/Panel.qml"
rg -q 'showTransientFeedback\("Endpoint copied"\)' "$plugin_dir/Panel.qml"
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
trap 'rm -rf -- "$test_root"' EXIT
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

if command -v omarchy >/dev/null; then
  omarchy plugin validate "$plugin_dir" >/dev/null
fi

printf 'Standalone Local AI plugin checks passed\n'
