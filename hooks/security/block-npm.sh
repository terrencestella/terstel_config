#!/bin/bash
CMD=$(jq -r '.tool_input.command // ""')
echo "$CMD" | grep -qE '(^|[^[:alnum:]_-])(npm|npx)([^[:alnum:]_-]|$)' || exit 0
echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Use bun instead of npm/npx. Equivalents: npm install = bun install, npm run = bun run, npx = bunx, npm install <pkg> = bun add <pkg>, npm uninstall <pkg> = bun remove <pkg>"}}'
