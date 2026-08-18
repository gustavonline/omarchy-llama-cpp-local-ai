#!/usr/bin/env bash
set -euo pipefail

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

jq -e '
  .schemaVersion == 1 and
  .id == "io.github.gustavonline.local-ai" and
  (.kinds | index("bar-widget")) != null and
  .entryPoints.barWidget == "Panel.qml"
' "$plugin_dir/manifest.json" >/dev/null

bash -n "$plugin_dir/local-ai-control"
"$plugin_dir/local-ai-control" --config "$plugin_dir/local-ai.example.json" status | jq -e '
  (.profile | type == "string") and
  (.state | type == "string") and
  (.endpoint | type == "string") and
  (.modelDirectory | type == "string") and
  (.profiles | type == "array") and
  (all(.profiles[]; (.id | type == "string") and (.ready | type == "boolean")))
' >/dev/null

if command -v omarchy >/dev/null; then
  omarchy plugin validate "$plugin_dir" >/dev/null
fi

printf 'Standalone Local AI plugin checks passed\n'
