#!/usr/bin/env bash
set -euo pipefail

installed=$(claude plugins list --json 2>/dev/null | jq -r '.[].id')

jq -r '.enabledPlugins | keys[]' ~/.claude/settings.json | while read -r plugin; do
  if ! echo "$installed" | grep -qx "$plugin"; then
    echo "Installing missing plugin: $plugin"
    claude plugins install "$plugin"
  fi
done
