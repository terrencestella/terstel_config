#!/usr/bin/env bash
set -euo pipefail

# settings.json (and its extraKnownMarketplaces/enabledPlugins) syncs across
# machines, but the actual marketplace clones and plugin caches under
# ~/.claude/plugins/ are machine-local and never sync. So on a machine that
# has never run `claude plugin marketplace add`, every install below fails
# with "not found in marketplace" even though the marketplace name is known.
# Register any missing marketplace from extraKnownMarketplaces first.
known_marketplaces=$(claude plugin marketplace list --json 2>/dev/null | jq -r '.[].name')

jq -r '.extraKnownMarketplaces // {} | to_entries[] | "\(.key) \(.value.source.repo)"' ~/.claude/settings.json | while read -r name repo; do
  if ! echo "$known_marketplaces" | grep -qx "$name"; then
    echo "Adding marketplace: $name ($repo)"
    claude plugin marketplace add "$repo" || echo "  Failed to add marketplace $name (will retry next session)" >&2
  fi
done

installed=$(claude plugin list --json 2>/dev/null | jq -r '.[].id')

jq -r '.enabledPlugins | keys[]' ~/.claude/settings.json | while read -r plugin; do
  if ! echo "$installed" | grep -qx "$plugin"; then
    echo "Installing missing plugin: $plugin"
    claude plugin install "$plugin" || echo "  Failed to install $plugin (will retry next session)" >&2
  fi
done
